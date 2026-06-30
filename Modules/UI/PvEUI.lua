--[[
    Warband Nexus - PvE Progress Tab
    Great Vault, M+, and raid lockouts per character (reads PvECacheService / db.global.pveCache).

    WN_FACTORY: Column picker catcher + Hide-menu fullscreen catcher stay raw Buttons (FULLSCREEN_DIALOG
    strata + propagate flags). Drawer shells use `ns.UI.Factory` where parity allows; Vault slot Buttons
    and dynamic scroll children keep CreateFrame paths documented inline.
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

local WarbandNexus = ns.WarbandNexus
local E = ns.Constants and ns.Constants.EVENTS
local FontManager = ns.FontManager  -- Centralized font management

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

local function PveBrightHex()
    return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
end

local function PveMplusScoreColor500()
    if ns.UI_IsLightMode and ns.UI_IsLightMode() then
        return PveBrightHex()
    end
    return "|cffffffff"
end

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local BuildCollapsibleSectionOpts = ns.UI_BuildCollapsibleSectionOpts
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
local ColumnOrder = ns.ColumnOrder

-- Import shared UI layout constants
-- (ns.GetUILayoutTokens never existed anywhere — the guard branch was dead.)
local function GetLayout()
    return ns.UI_LAYOUT or {}
end
local ROW_HEIGHT = GetLayout().rowHeight or 26
local ROW_SPACING = GetLayout().rowSpacing or 28
local HEADER_SPACING = GetLayout().headerSpacing or 44
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().sideMargin or 10
local TOP_MARGIN = GetLayout().topMargin or 8

-- PvE inline grid: min width for horizontal scroll; column headers live in scrollChild (not columnHeaderClip).
-- Left prefix through iLvl matches Characters row chrome; inline grid starts at PvE_ComputeInlineColumnsStartPx.
local PVE_CHAR_HEADER_H_MARGIN = 20                -- char row inset 10 + 10
local PVE_COLUMN_HEADER_PAD = 2
local PVE_COL_SPACING = 4                        -- uniform baseline spacing for symmetric header rhythm
local PVE_KEY_TO_VAULT_GAP = 6                   -- currency block ↔ vault block
local PVE_VAULT_CLUSTER_GAP = 6                  -- Raid | Dungeon | World internal spacing
local PVE_COL_RIGHT_MARGIN = 6
local PVE_COL_WIDTH_PAD = 6
local PVE_COL_WIDTH_MIN = 28
--- Floor widths (adaptive pass may grow per content).
local PVE_DAWNCREST_COL_W = 48
local PVE_COFFER_COL_W = 52
local PVE_KEY_COL_W = 36
local PVE_VAULT_COL_W = 54
local PVE_VAULT_COL_ILVL_W = 68
local PVE_VAULT_COL_PROGRESS_W = 72
local PVE_VAULT_COL_REWARD_PROGRESS_W = 88
local PVE_BOUNTIFUL_COL_W = 28
local PVE_STATUS_COL_W = 64
local PVE_DUNDUN_COL_W = 36
local PVE_VOIDCORE_COL_W = 40
local PVE_MANAFLUX_COL_W = 40
local PVE_DUNDUN_ID = 3376
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

local PVE_COMPACT_CREST_BY_ID = {
    [3383] = { text = GetLocalizedText("PVE_CREST_ADV", "Adventurer"), hex = "9d9d9d" },
    [3341] = { text = GetLocalizedText("PVE_CREST_VET", "Veteran"), hex = "1eff00" },
    [3343] = { text = GetLocalizedText("PVE_CREST_CHAMP", "Champion"), hex = "0070dd" },
    [3345] = { text = GetLocalizedText("PVE_CREST_HERO", "Hero"), hex = "a335ee" },
    [3347] = { text = GetLocalizedText("PVE_CREST_MYTH", "Myth"), hex = "ff8000" },
}

local function PvE_BuildCompactHeaderLabel(col)
    if not col then return "", "ffffff" end
    local rawLabel = col.headerLabel or col.tooltipTitle or ""
    if not rawLabel or rawLabel == "" then return "", "ffffff" end
    if issecretvalue and issecretvalue(rawLabel) then return "", "ffffff" end

    local key = col.key or ""
    if key == "coffer_shards" then
        return GetLocalizedText("PVE_COMPACT_COFFER_SHARD", "Coffer Shard"), "ffffff"
    elseif key == "restored_key" then
        return GetLocalizedText("PVE_COMPACT_RESTORED", "Restored"), "ffffff"
    elseif key == "shard_of_dundun" then
        return GetLocalizedText("PVE_COMPACT_DUNDUN", "Dundun"), "ffffff"
    elseif key == "voidcore" then
        return GetLocalizedText("PVE_COMPACT_VOIDCORE", "Voidcore"), "ffffff"
    elseif key == "manaflux" then
        return GetLocalizedText("PVE_COMPACT_MANAFLUX", "Manaflux"), "ffffff"
    elseif key == "slot1" then
        return GetLocalizedText("PVE_HEADER_RAID_SHORT", "Raid"), "ffffff"
    elseif key == "slot2" then
        return GetLocalizedText("VAULT_DUNGEON", "Dungeon"), "ffffff"
    elseif key == "slot3" then
        return GetLocalizedText("VAULT_SLOT_WORLD", "World"), "ffffff"
    elseif key == "bountiful" then
        return GetLocalizedText("PVE_HEADER_MAP_SHORT", "Bounty"), "ffffff"
    elseif key == "vault_status" then
        return GetLocalizedText("PVE_HEADER_STATUS_SHORT", "Status"), "ffffff"
    elseif key:match("^crest_") then
        local crestID = tonumber(key:match("^crest_(%d+)$"))
        if crestID and PVE_COMPACT_CREST_BY_ID[crestID] then
            local entry = PVE_COMPACT_CREST_BY_ID[crestID]
            return entry.text, entry.hex
        end
        return GetLocalizedText("PVE_CREST_GENERIC", "Crest"), "ffffff"
    end
    return "", "ffffff"
end

local function GetLowLevelHideThreshold(profile)
    if ns.UI_GetLowLevelHideThreshold then
        return ns.UI_GetLowLevelHideThreshold(profile)
    end
    if not profile then return 0 end
    local threshold = tonumber(profile.hideLowLevelThreshold) or 0
    if threshold >= 90 then return 90 end
    if threshold >= 80 then return 80 end
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
    if ns.UI_GetLowLevelHideLabel then
        return ns.UI_GetLowLevelHideLabel(threshold)
    end
    if threshold == 90 then return GetLocalizedText("HIDE_FILTER_LEVEL_90", "Level 90") end
    if threshold == 80 then return GetLocalizedText("HIDE_FILTER_LEVEL_80", "Level 80") end
    return GetLocalizedText("HIDE_FILTER_STATE_OFF", "Off")
end

local function ApplyLowLevelHideThreshold(addon, threshold)
    if ns.UI_ApplyLowLevelHideThreshold then
        ns.UI_ApplyLowLevelHideThreshold(addon, threshold)
        return
    end
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

ns.PvEUI = ns.PvEUI or {}
ns.PvEUI.GetLowLevelHideThreshold = GetLowLevelHideThreshold
ns.PvEUI.GetLowLevelHideLabel = GetLowLevelHideLabel
ns.PvEUI.ApplyLowLevelHideThreshold = ApplyLowLevelHideThreshold

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
    charRows = {}, -- [charKey] = { header, detail, expandIcon }
    colHeaderRow = nil,
    colHeaderHits = {}, -- [colKey] = hitFrame
    columnLayout = { sig = nil, widths = {} },
    columnDefsColSig = nil,
    columnDefs = nil,
    vaultTrackColW = nil,
    sectionShells = {}, -- [expandKey] = { header, body }
}
local _pveVaultStatusScratch = {}

function ns.PvE_ClearVaultStatusScratch()
    for k in pairs(_pveVaultStatusScratch) do
        _pveVaultStatusScratch[k] = nil
    end
end

--- Vault claim / reward cache changed: clear per-row status scratch (drawSig includes vault roster).
function ns.PvE_InvalidateBodyPaint()
    ns.PvE_ClearVaultStatusScratch()
end

local function PvE_EnsureDrawPoolHolder()
    local h = _pveDrawPool.holder
    if not h then
        local PUF = ns.UI and ns.UI.Factory
        h = PUF and PUF:CreateContainer(UIParent, 1, 1, false)
        if not h then
            h = CreateFrame("Frame", nil, UIParent)
            h:SetSize(1, 1)
        end
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
        local charRows = pool.charRows
        if charRows then
            for ck, row in pairs(charRows) do
                if not currentKeySet[ck] then
                    if row.header then
                        row.header:Hide()
                        row.header:SetParent(holder)
                    end
                    if row.detail then
                        row.detail:Hide()
                        row.detail:SetParent(holder)
                    end
                    charRows[ck] = nil
                end
            end
        end
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
        if pool.columnLayout then
            pool.columnLayout.sig = nil
        end
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

--- Park pooled column labels before rebuilding the header row (stale anchors/text caused orphan labels).
local function PvEParkAllColHeaderLabels()
    local pool = _pveDrawPool
    local holder = PvE_EnsureDrawPoolHolder()
    for _, fs in pairs(pool.headerLabels) do
        if fs then
            fs:Hide()
            fs:ClearAllPoints()
            fs:SetText("")
            fs:SetParent(holder)
        end
    end
end

local function PvEAcquireColHeaderLabel(colHeaderRow, colKey, hitFrame, compactLabel, compactHex, colWidth)
    local pool = _pveDrawPool
    local fs = pool.headerLabels[colKey]
    if not fs then
        fs = FontManager:CreateFontString(colHeaderRow, "small", "OVERLAY")
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
    local hex = compactHex or "ffffff"
    if hex == "ffffff" and ns.UI_GetTextRoleHex then
        local roleHex = ns.UI_GetTextRoleHex("Bright")
        hex = roleHex and roleHex:match("cff(%x%x%x%x%x%x)") or hex
    end
    fs:SetText("|cff" .. hex .. compactLabel .. "|r")
    if ns.UI_IsLightMode and ns.UI_IsLightMode() then
        fs:SetShadowOffset(0, 0)
    else
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
    end
    return fs
end

local function PvE_StripMarkupForMeasure(text)
    if not text or text == "" then return "" end
    if issecretvalue and issecretvalue(text) then return "" end
    local s = tostring(text)
    s = s:gsub("|T.-|t", "@@@")
    s = s:gsub("|A.-|a", "@@@")
    s = s:gsub("|c%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
end

local function PvE_MeasurePlainWidth(fs, text)
    if not fs then return 0 end
    fs:SetText(PvE_StripMarkupForMeasure(text))
    return fs:GetStringWidth() or 0
end

local function PvE_GetVaultStatusCached(addon, charKey)
    if not addon or not charKey or not addon.GetVaultStatusForChar then return nil end
    local hit = _pveVaultStatusScratch[charKey]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local vs = addon:GetVaultStatusForChar(charKey)
    _pveVaultStatusScratch[charKey] = vs or false
    return vs
end

--- Grow each column width to fit header label + widest cell value across the roster.
local function PvE_ApplyAdaptiveColumnWidths(columns, ctx)
    if not columns or #columns == 0 or not ctx or not ctx.characters or #ctx.characters == 0 then return end
    local bodyFs = PvE_GetDrawPoolMeasureFS()
    local headerFs = _pveDrawPool.headerMeasureFs
    if not headerFs then
        headerFs = FontManager:CreateFontString(PvE_EnsureDrawPoolHolder(), "small", "OVERLAY")
        headerFs:Hide()
        _pveDrawPool.headerMeasureFs = headerFs
    end
    local addon = ctx.addon
    local getKey = ctx.getCharKey
    local formatSeasonShift = ctx.formatSeasonShift
    local compactShift = ctx.compactShift ~= false
    local buildCompactHeader = ctx.buildCompactHeader
    local formatNum = ctx.formatNumber or FormatNumber
    local emDash = ctx.emDash or "\226\128\148"
    local iconSz = ctx.colIconSize or 24
    local crests = ctx.crests or {}
    local crestByKey = {}
    for i = 1, #crests do
        crestByKey["crest_" .. tostring(crests[i].id)] = crests[i].id
    end

    local function measureSeasonCell(cd)
        if not cd then return 0 end
        local fmtCurrent = ns.UI_FormatPvECurrencyCurrentLine
        local fmtWeekly = ns.UI_FormatPvECurrencyWeeklyLine
        if fmtCurrent and fmtWeekly then
            local wCurrent = PvE_MeasurePlainWidth(bodyFs, fmtCurrent(cd))
            local wWeekly = PvE_MeasurePlainWidth(bodyFs, fmtWeekly(cd))
            return math.max(wCurrent, wWeekly)
        end
        if not formatSeasonShift then return 0 end
        local wNormal = PvE_MeasurePlainWidth(bodyFs, formatSeasonShift(cd, false, compactShift))
        local wShift = PvE_MeasurePlainWidth(bodyFs, formatSeasonShift(cd, true, compactShift))
        return math.max(wNormal, wShift)
    end

    local function measureCell(col, charKey)
        local key = col.key
        if not addon or not charKey then return 0 end
        if crestByKey[key] then
            local cd = addon.GetCurrencyData and addon:GetCurrencyData(crestByKey[key], charKey)
            if formatSeasonShift and cd then
                return measureSeasonCell(cd)
            end
            local q = cd and cd.quantity or 0
            return PvE_MeasurePlainWidth(bodyFs, q > 0 and formatNum(q) or emDash)
        end
        if key == "coffer_shards" and ctx.shardsId then
            local cd = addon.GetCurrencyData and addon:GetCurrencyData(ctx.shardsId, charKey)
            if formatSeasonShift and cd then
                return measureSeasonCell(cd)
            end
            local q = cd and cd.quantity or 0
            return PvE_MeasurePlainWidth(bodyFs, q > 0 and formatNum(q) or emDash)
        end
        if key == "restored_key" and ctx.keyId then
            local cd = addon.GetCurrencyData and addon:GetCurrencyData(ctx.keyId, charKey)
            if cd then
                return measureSeasonCell(cd)
            end
            return PvE_MeasurePlainWidth(bodyFs, emDash)
        end
        if key == "shard_of_dundun" and ctx.dundunId then
            local cd = addon.GetCurrencyData and addon:GetCurrencyData(ctx.dundunId, charKey)
            if formatSeasonShift and cd then
                return measureSeasonCell(cd)
            end
            local q = tonumber(cd and cd.quantity) or 0
            return PvE_MeasurePlainWidth(bodyFs, q > 0 and formatNum(q) or emDash)
        end
        if key == "voidcore" and ctx.voidcoreId then
            local cd = addon.GetCurrencyData and addon:GetCurrencyData(ctx.voidcoreId, charKey)
            if formatSeasonShift and cd then
                return measureSeasonCell(cd)
            end
            local q = tonumber(cd and cd.quantity) or 0
            return PvE_MeasurePlainWidth(bodyFs, q > 0 and formatNum(q) or emDash)
        end
        if key == "manaflux" and ctx.manafluxId then
            local cd = addon.GetCurrencyData and addon:GetCurrencyData(ctx.manafluxId, charKey)
            if formatSeasonShift and cd then
                return measureSeasonCell(cd)
            end
            local q = tonumber(cd and cd.quantity) or 0
            return PvE_MeasurePlainWidth(bodyFs, q > 0 and formatNum(q) or emDash)
        end
        if key == "slot1" or key == "slot2" or key == "slot3" then
            local pve = addon.GetPvEData and addon:GetPvEData(charKey) or {}
            local acts = pve.vaultActivities or {}
            local claim = false
            local vs = PvE_GetVaultStatusCached(addon, charKey)
            claim = vs and vs.isReady == true
            local formatVault = ctx.formatVaultTrack
            if formatVault then
                local list, typeName, total
                if key == "slot1" then
                    list, typeName, total = acts.raids, "Raid", acts.raids and #acts.raids or 3
                elseif key == "slot2" then
                    list, typeName, total = acts.mythicPlus, "M+", acts.mythicPlus and #acts.mythicPlus or 3
                else
                    list, typeName, total = acts.world, "World", acts.world and #acts.world or 3
                end
                return PvE_MeasurePlainWidth(bodyFs, formatVault(list, total, typeName, claim, iconSz))
            end
        end
        if key == "bountiful" then
            local wIcon = PvE_MeasurePlainWidth(bodyFs, "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t")
            local wProg = PvE_MeasurePlainWidth(bodyFs, "0 / 1")
            return math.max(iconSz, wIcon, wProg)
        end
        if key == "vault_status" then
            local vs = PvE_GetVaultStatusCached(ctx.addon, charKey)
            if not vs then
                return PvE_MeasurePlainWidth(bodyFs, emDash)
            end
            if vs.isReady then
                return PvE_MeasurePlainWidth(bodyFs, GetLocalizedText("VAULT_READY_TO_CLAIM", "Ready to Claim"))
            end
            if vs.claimedThisWeek and not vs.isReady then
                return PvE_MeasurePlainWidth(bodyFs, GetLocalizedText("VAULT_PENDING", "Pending..."))
            end
            if (vs.readySlots or 0) > 0 then
                local fmt = GetLocalizedText("VAULT_SLOTS_SHORT_FORMAT", "%d Slots")
                return PvE_MeasurePlainWidth(bodyFs, fmt:format(tonumber(vs.readySlots) or 0))
            end
            return PvE_MeasurePlainWidth(bodyFs, GetLocalizedText("VAULT_PENDING", "Pending..."))
        end
        return 0
    end

    for ci = 1, #columns do
        local col = columns[ci]
        local maxW = PVE_COL_WIDTH_MIN
        if buildCompactHeader then
            local compactLabel = buildCompactHeader(col)
            if compactLabel and compactLabel ~= "" then
                maxW = math.max(maxW, PvE_MeasurePlainWidth(headerFs, compactLabel))
            end
        elseif col.headerLabel and col.headerLabel ~= "" then
            maxW = math.max(maxW, PvE_MeasurePlainWidth(headerFs, col.headerLabel))
        end
        if col.icon or col.iconAtlas then
            maxW = math.max(maxW, iconSz)
        end
        for chi = 1, #ctx.characters do
            local ck = getKey and getKey(ctx.characters[chi])
            if ck then
                maxW = math.max(maxW, measureCell(col, ck))
            end
        end
        col.width = math.max(PVE_COL_WIDTH_MIN, math.ceil(maxW) + PVE_COL_WIDTH_PAD)
    end
end

local function PvE_BuildColumnLayoutSig(rosterSig, colSig, nameWidth, vbProfile)
    local vb = vbProfile or {}
    return table.concat({
        rosterSig or "",
        colSig or "",
        tostring(nameWidth or 0),
        vb.showRewardProgress and "1" or "0",
        vb.showRewardItemLevel and "1" or "0",
    }, "\2")
end

local function PvE_ApplyCachedColumnWidths(columns, layoutCache)
    if not columns or not layoutCache or not layoutCache.widths then return false end
    local widths = layoutCache.widths
    for ci = 1, #columns do
        local col = columns[ci]
        local w = widths[col.key]
        if w then
            col.width = w
        end
    end
    return true
end

local function PvE_SaveColumnLayoutCache(layoutCache, sig, columns)
    if not layoutCache or not columns then return end
    layoutCache.sig = sig
    local widths = layoutCache.widths
    for k in pairs(widths) do widths[k] = nil end
    for ci = 1, #columns do
        widths[columns[ci].key] = columns[ci].width
    end
end

local COL_HEADER_HEIGHT_PVE = 48

local function PveBuildToolbarDrawSig(profile)
    if not profile then return "" end
    local sortKey = (profile and ns.CharacterService and ns.CharacterService.GetTabSortKey)
        and ns.CharacterService:GetTabSortKey(profile, "pve") or "default"
    local sortAsc = (profile.pveSort and profile.pveSort.ascending) and "1" or "0"
    local sec = (profile.pveSectionFilter and profile.pveSectionFilter.sectionKey) or "all"
    local ll = GetLowLevelHideThreshold(profile)
    return table.concat({ sortKey, sortAsc, sec, tostring(ll) }, "\1")
end

local function PveOrderColumnKeysBySequence(keys, seq)
    if not keys or #keys == 0 then return keys end
    if not seq or #seq == 0 then return keys end
    local keySet = {}
    for i = 1, #keys do keySet[keys[i]] = true end
    local ordered = {}
    for si = 1, #seq do
        local sk = seq[si]
        if keySet[sk] then
            ordered[#ordered + 1] = sk
            keySet[sk] = nil
        end
    end
    for i = 1, #keys do
        local k = keys[i]
        if keySet[k] then
            ordered[#ordered + 1] = k
            keySet[k] = nil
        end
    end
    return ordered
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
    if ex.shard_of_dundun == nil then ex.shard_of_dundun = true end
    return ex
end

local function PveBuildFastRosterSig(addon, profile)
    if not addon or not addon.GetAllCharacters then return "0" end
    local allCharacters = addon:GetAllCharacters()
    local minLevel = GetLowLevelHideThreshold(profile)
    local parts = {}
    for i = 1, #allCharacters do
        local char = allCharacters[i]
        local lvl = tonumber(char.level) or 0
        if char.isTracked ~= false and (minLevel == 0 or lvl >= minLevel) then
            local rk = (ns.PvEUI and ns.PvEUI.GetCanonicalKeyForChar and ns.PvEUI.GetCanonicalKeyForChar(char))
                or (char._key or char.guid)
            if rk then parts[#parts + 1] = rk end
        end
    end
    table.sort(parts)
    return tostring(#parts) .. "\0" .. table.concat(parts, "\1")
end

local function PveBuildSectionExpandSig(profile)
    if not profile or not profile.ui then return "" end
    local parts = {
        (profile.ui.pveFavoritesExpanded == true) and "1" or "0",
        (profile.ui.pveCharactersExpanded == true) and "1" or "0",
    }
    local cg = profile.characterGroupExpanded
    if cg then
        local gparts = {}
        for k, v in pairs(cg) do
            if v == true then gparts[#gparts + 1] = tostring(k) end
        end
        table.sort(gparts)
        parts[#parts + 1] = table.concat(gparts, ",")
    end
    return table.concat(parts, "\1")
end

local function PveVaultActSig(acts)
    if not acts then return "-" end
    if acts.isPostReset then return "post" end
    local chunks = {}
    local cats = { "raids", "mythicPlus", "world" }
    for ci = 1, #cats do
        local list = acts[cats[ci]]
        if list then
            for si = 1, #list do
                local a = list[si]
                chunks[#chunks + 1] = string.format(
                    "%d,%d",
                    tonumber(a and a.progress) or 0,
                    tonumber(a and a.threshold) or 0
                )
            end
        end
    end
    return table.concat(chunks, ";")
end

--- Vault reward + activity snapshot for drawSig (bust fast-path when only vault rows change).
local function PveBuildVaultRosterSig(addon, profile)
    if not addon or not addon.GetAllCharacters then return "" end
    local gv = addon.db and addon.db.global and addon.db.global.pveCache
        and addon.db.global.pveCache.greatVault
    if not gv then return "" end
    local lookup = ns.LookupPvECacheSubtable
    local allCharacters = addon:GetAllCharacters()
    local minLevel = GetLowLevelHideThreshold(profile)
    local parts = {}
    for i = 1, #allCharacters do
        local char = allCharacters[i]
        local lvl = tonumber(char.level) or 0
        if char.isTracked ~= false and (minLevel == 0 or lvl >= minLevel) then
            local rk = (ns.PvEUI and ns.PvEUI.GetCanonicalKeyForChar and ns.PvEUI.GetCanonicalKeyForChar(char))
                or (char._key or char.guid)
            if rk then
                local rewards = gv.rewards and (lookup and lookup(gv.rewards, rk) or gv.rewards[rk])
                local acts = gv.activities and (lookup and lookup(gv.activities, rk) or gv.activities[rk])
                parts[#parts + 1] = table.concat({
                    rk,
                    rewards and rewards.hasAvailableRewards and "1" or "0",
                    tostring(rewards and rewards.claimedAt or 0),
                    tostring(rewards and rewards.claimedResetTime or 0),
                    PveVaultActSig(acts),
                }, ":")
            end
        end
    end
    table.sort(parts)
    return table.concat(parts, "\1")
end

local function PveBuildFullDrawSig(addon, profile, rosterSig, colSig)
    local vb = profile and profile.vaultButton or {}
    return table.concat({
        PveBuildToolbarDrawSig(profile),
        colSig or "",
        rosterSig or "",
        PveBuildSectionExpandSig(profile),
        (vb.showRewardProgress and "1" or "0"),
        (vb.showRewardItemLevel and "1" or "0"),
        PveBuildVaultRosterSig(addon, profile),
    }, "\2")
end

local function PveCopyColumnDefs(columns)
    if not columns then return nil end
    local copy = {}
    for i = 1, #columns do
        local c = columns[i]
        copy[i] = {
            key = c.key,
            label = c.label,
            width = c.width,
            icon = c.icon,
            iconAtlas = c.iconAtlas,
            crestCurrencyId = c.crestCurrencyId,
            tooltipTitle = c.tooltipTitle,
            headerLabel = c.headerLabel,
            headerIconIsAtlas = c.headerIconIsAtlas,
        }
    end
    return copy
end

local function PveEstimateScrollBodyHeight(charCount, sectionCount)
    local rows = tonumber(charCount) or 0
    local secs = tonumber(sectionCount) or 3
    local rowH = 46
    local secH = 40
    return COL_HEADER_HEIGHT_PVE + PVE_COLUMN_HEADER_PAD + secs * secH + rows * (rowH + 2) + 96
end

local function PveTeardownKeptBodyArtifacts(parent)
    local pool = _pveDrawPool
    local rb = ns.UI_RecycleBin
    if pool.colHeaderRow then
        pool.colHeaderRow._wnKeepOnTabSwitch = nil
        pool.colHeaderRow:Hide()
        if rb and pool.colHeaderRow.SetParent then
            pool.colHeaderRow:SetParent(rb)
        end
    end
    local shells = pool.sectionShells
    if shells then
        for _, sh in pairs(shells) do
            if sh.header then
                sh.header._wnKeepOnTabSwitch = nil
                sh.header:Hide()
                if rb and sh.header.SetParent then sh.header:SetParent(rb) end
            end
            if sh.body then
                sh.body._wnKeepOnTabSwitch = nil
                sh.body:Hide()
                if rb and sh.body.SetParent then sh.body:SetParent(rb) end
            end
        end
        for k in pairs(shells) do shells[k] = nil end
    end
    if parent then
        parent._pveBodyReady = nil
    end
end

--- Reposition cached PvE fixedHeader chrome (WN-PERF tab revisit).
local function RepositionPveFixedHeader(mf, hdrCache, headerParent, chrome, headerYOffset, contentSide, scrollChild)
    local titleCard = hdrCache.titleCard
    titleCard:SetParent(headerParent)
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:ClearAllPoints()
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    end
    titleCard:Show()
    if hdrCache.sortBtn then hdrCache.sortBtn:Show() end
    if hdrCache.hideBtn then hdrCache.hideBtn:Show() end
    if hdrCache.columnsBtn then hdrCache.columnsBtn:Show() end
    if hdrCache.resetTimer then hdrCache.resetTimer:Show() end
    if ns.UI_HideTitleCardExpandCollapseControls then
        ns.UI_HideTitleCardExpandCollapseControls(scrollChild)
    end
    if ns.UI_AdvanceTabChromeYOffset then
        return ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight(), 0)
    end
    return headerYOffset + (titleCard:GetHeight() or 64)
end

function ns.PvEUI.InvalidateBodyCache(parent)
    PveTeardownKeptBodyArtifacts(parent)
    if parent then
        parent._pveDrawSig = nil
        parent._pveLastBodyEstimate = nil
    end
end

local PvEUI_DrawPvEProgressBody

local PVE_CHAR_ROW_HEADER_H = 46

local function PvEUI_MeasureScrollChildExtent(scrollChild)
    if not scrollChild or not scrollChild.GetTop then return nil end
    local pTop = scrollChild:GetTop()
    if not pTop then return nil end
    local tail = scrollChild._pveLayoutTailBody
    if tail and tail:IsShown() and tail.GetBottom then
        local bot = tail:GetBottom()
        if bot then
            return math.max(1, pTop - bot)
        end
    end
    local lowest = pTop
    local kids = { scrollChild:GetChildren() }
    for i = 1, #kids do
        local c = kids[i]
        if c and c:IsShown() then
            local b = c:GetBottom()
            if b and b < lowest then
                lowest = b
            end
        end
    end
    return math.max(1, pTop - lowest)
end

local function PvEUI_SyncPveScrollChildExtent(scrollChild, scrollFrameRef)
    if not scrollChild then return end
    local pad = 8
    local extent = PvEUI_MeasureScrollChildExtent(scrollChild)
    if not extent then
        local tail = scrollChild._pveLayoutTailBody
        if tail and scrollChild.GetTop and tail.GetBottom then
            local pTop = scrollChild:GetTop()
            local bot = tail:GetBottom()
            if pTop and bot then
                extent = math.max(1, pTop - bot)
            end
        end
    end
    if not extent then return end
    local viewportH = (scrollFrameRef and scrollFrameRef.GetHeight and scrollFrameRef:GetHeight()) or 0
    scrollChild:SetHeight(math.max(viewportH, extent + pad))
    scrollChild._pvePaintedCoreH = math.max(1, extent)
    if scrollFrameRef and scrollFrameRef.GetVerticalScrollRange and scrollFrameRef.GetVerticalScroll and scrollFrameRef.SetVerticalScroll then
        local maxV = scrollFrameRef:GetVerticalScrollRange() or 0
        local cur = scrollFrameRef:GetVerticalScroll() or 0
        scrollFrameRef:SetVerticalScroll(math.min(math.max(cur, 0), maxV))
    end
end

local PVE_SECTION_SHELL_GAP = 4

local function PvEUI_ResolveCharDetailPaintHeight(detail)
    if not detail or not detail:IsShown() then
        return 0.1
    end
    local h = detail._wnSectionFullH or detail:GetHeight() or 0.1
    if h < 2 then
        return 0.1
    end
    return h
end

--- Re-anchor Favorites / custom / Characters section headers after row-host height changes.
local function PvEUI_EnsurePveSectionShellOrder(scrollChild)
    if scrollChild._pveSectionShellOrder and #scrollChild._pveSectionShellOrder > 0 then
        return scrollChild._pveSectionShellOrder
    end
    local shells = _pveDrawPool and _pveDrawPool.sectionShells
    if not shells then return nil end
    local ordered = {}
    local known = { "pveFavoritesExpanded", "pveCharactersExpanded" }
    for ki = 1, #known do
        local key = known[ki]
        if shells[key] and shells[key].header then
            ordered[#ordered + 1] = key
        end
    end
    for key, sh in pairs(shells) do
        if type(key) == "string" and key:match("^cgrp_") and sh and sh.header then
            local dup = false
            for oi = 1, #ordered do
                if ordered[oi] == key then dup = true break end
            end
            if not dup then
                ordered[#ordered + 1] = key
            end
        end
    end
    scrollChild._pveSectionShellOrder = ordered
    return ordered
end

local function PvEUI_MeasureRowHostContentHeight(rowHost)
    if not rowHost or not rowHost.GetTop then return nil end
    local pTop = rowHost:GetTop()
    if not pTop then return nil end
    local lowest = pTop
    local kids = { rowHost:GetChildren() }
    for i = 1, #kids do
        local c = kids[i]
        if c and c:IsShown() then
            local b = c:GetBottom()
            if b and b < lowest then
                lowest = b
            end
        end
    end
    return math.max(0.1, pTop - lowest)
end

--- Row order for reflow: use paint list, or discover headers parented to rowHost (live collapse without repaint).
local function PvEUI_DiscoverCharKeysOnRowHost(rowHost)
    local keys = rowHost._pveCharKeysOrdered
    if keys and #keys > 0 then
        return keys
    end
    local pool = _pveDrawPool and _pveDrawPool.charRows
    if not pool or not rowHost then
        return keys or {}
    end
    local scratch = {}
    for charKey, row in pairs(pool) do
        if row and row.header and row.header:GetParent() == rowHost then
            local top = row.header:GetTop()
            scratch[#scratch + 1] = { key = charKey, top = top or 0 }
        end
    end
    table.sort(scratch, function(a, b)
        return a.top > b.top
    end)
    keys = {}
    for i = 1, #scratch do
        keys[i] = scratch[i].key
    end
    rowHost._pveCharKeysOrdered = keys
    return keys
end

--- Re-chain pooled character headers/details after live expand/collapse (anchors alone are not enough).
local function PvEUI_ReflowSectionCharRows(rowHost, interRowGap)
    if not rowHost then return 0.1 end
    local keys = PvEUI_DiscoverCharKeysOnRowHost(rowHost)
    local pool = _pveDrawPool and _pveDrawPool.charRows
    if not pool or #keys == 0 then
        local measured = PvEUI_MeasureRowHostContentHeight(rowHost)
        if measured then
            rowHost:SetHeight(measured)
            rowHost._pveRunningH = measured
            rowHost._wnSectionFullH = measured
            rowHost._pvePaintedSectionH = measured
            return measured
        end
        return rowHost:GetHeight() or 0.1
    end
    local gap = interRowGap or rowHost._pveRowGap or 0
    local prev = nil
    local runningH = 0
    for ki = 1, #keys do
        local row = pool[keys[ki]]
        if row and row.header and row.detail then
            local hdr = row.header
            local det = row.detail
            hdr:ClearAllPoints()
            if prev then
                hdr:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
                hdr:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -gap)
            else
                hdr:SetPoint("TOPLEFT", rowHost, "TOPLEFT", 0, 0)
                hdr:SetPoint("TOPRIGHT", rowHost, "TOPRIGHT", 0, 0)
            end
            det:ClearAllPoints()
            det:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, 0)
            det:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
            local hdrH = hdr:GetHeight() or PVE_CHAR_ROW_HEADER_H
            local detH = PvEUI_ResolveCharDetailPaintHeight(det)
            det:SetHeight(detH)
            if detH >= 2 then
                det:Show()
            else
                det:Hide()
            end
            det._pvePaintedDetailH = detH
            runningH = runningH + hdrH + detH
            if ki < #keys then
                runningH = runningH + gap
            end
            prev = det
        end
    end
    local secH = math.max(0.1, runningH)
    local measured = PvEUI_MeasureRowHostContentHeight(rowHost)
    if measured and measured > 0.1 then
        secH = measured
    end
    rowHost._pveRunningH = secH
    rowHost._wnSectionFullH = secH
    rowHost._pvePaintedSectionH = secH
    rowHost:SetHeight(secH)
    return secH
end

local function PvEUI_ReflowPveSectionShellChain(scrollChild)
    if not scrollChild then return end
    local order = PvEUI_EnsurePveSectionShellOrder(scrollChild)
    local shells = _pveDrawPool and _pveDrawPool.sectionShells
    if not order or not shells or #order == 0 then return end
    local gap = scrollChild._pveShellSectionGap or PVE_SECTION_SHELL_GAP
    local side = scrollChild._wnPveContentSide or SIDE_MARGIN or 12
    local yTop = scrollChild._pveColHeaderBottomY
    local prevBody = nil
    local layoutTail = nil
    for i = 1, #order do
        local sh = shells[order[i]]
        if sh and sh.header and sh.body then
            sh.header:ClearAllPoints()
            if prevBody then
                sh.header:SetPoint("TOPLEFT", prevBody, "BOTTOMLEFT", 0, -gap)
            elseif yTop then
                sh.header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", side, -yTop)
            else
                sh.header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", side, 0)
            end
            sh.body:ClearAllPoints()
            sh.body:SetPoint("TOPLEFT", sh.header, "BOTTOMLEFT", 0, 0)
            if sh.body:IsShown() then
                PvEUI_ReflowSectionCharRows(sh.body, sh.body._pveRowGap or gap)
                local bodyH = sh.body._pveRunningH or PvEUI_MeasureRowHostContentHeight(sh.body) or sh.body:GetHeight() or 0.1
                bodyH = math.max(0.1, bodyH)
                sh.body:SetHeight(bodyH)
                sh.body._wnSectionFullH = bodyH
                sh.body._pvePaintedSectionH = bodyH
                layoutTail = sh.body
            else
                sh.body:SetHeight(0.1)
            end
            prevBody = sh.body
        end
    end
    scrollChild._pveLayoutTailBody = layoutTail
end

function ns.PvEUI_ApplyLivePveSectionLayout(rowHost, scrollChild)
    if not scrollChild then return end
    local gap = (rowHost and rowHost._pveRowGap) or 0
    local shells = _pveDrawPool and _pveDrawPool.sectionShells
    local order = PvEUI_EnsurePveSectionShellOrder(scrollChild)
    if order and shells then
        for oi = 1, #order do
            local sh = shells[order[oi]]
            if sh and sh.body and sh.body:IsShown() then
                PvEUI_ReflowSectionCharRows(sh.body, sh.body._pveRowGap or gap)
            end
        end
    elseif rowHost then
        PvEUI_ReflowSectionCharRows(rowHost, gap)
    end
    PvEUI_ReflowPveSectionShellChain(scrollChild)
    local scrollFrameRef = scrollChild.GetParent and scrollChild:GetParent()
    PvEUI_SyncPveScrollChildExtent(scrollChild, scrollFrameRef)
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mf and scrollChild._pvePaintedCoreH and ns.UI_SyncMainTabScrollChrome then
        ns.UI_SyncMainTabScrollChrome(mf, scrollChild, scrollChild._pvePaintedCoreH)
    end
end

ns.PvEUI_ReflowSectionCharRows = PvEUI_ReflowSectionCharRows
ns.PvEUI_ReflowPveSectionShellChain = PvEUI_ReflowPveSectionShellChain
ns.PvEUI_SyncPveScrollChildExtent = PvEUI_SyncPveScrollChildExtent

local function PvEAcquireCharRowFrames(rowHost, charKey)
    local pool = _pveDrawPool
    pool.charRows = pool.charRows or {}
    local row = pool.charRows[charKey]
    if row and row.header and row.detail then
        row.header:SetParent(rowHost)
        row.detail:SetParent(rowHost)
        row.header:Show()
        return row.header, row.detail, row.expandIcon, true
    end
    row = {}
    pool.charRows[charKey] = row
    return nil, nil, nil, false
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
    if not addon then return end
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

local function GetPvEDefaultColumnKeyOrder(profile)
    local order = {}
    local crestDefs = GetPvEDawnCrestColumnDefinitions()
    for i = 1, #crestDefs do
        order[#order + 1] = "crest_" .. tostring(crestDefs[i].id)
    end
    order[#order + 1] = "coffer_shards"
    order[#order + 1] = "restored_key"
    order[#order + 1] = "shard_of_dundun"
    order[#order + 1] = "voidcore"
    order[#order + 1] = "manaflux"
    order[#order + 1] = "slot1"
    order[#order + 1] = "slot2"
    order[#order + 1] = "slot3"
    order[#order + 1] = "bountiful"
    order[#order + 1] = "vault_status"
    return order
end

--- Merge saved + default column keys into `profile.pveColumnOrder` without replacing the table
--- (picker reorder buttons keep a stable reference to the profile array).
local function EnsurePvEColumnOrder(profile)
    if not profile or not ColumnOrder then
        return GetPvEDefaultColumnKeyOrder(profile)
    end
    if type(profile.pveColumnOrder) ~= "table" then
        profile.pveColumnOrder = {}
    end
    local merged = ColumnOrder.MergeOrder(
        profile.pveColumnOrder,
        GetPvEDefaultColumnKeyOrder(profile),
        nil
    )
    for i = #profile.pveColumnOrder, 1, -1 do
        profile.pveColumnOrder[i] = nil
    end
    for i = 1, #merged do
        profile.pveColumnOrder[i] = merged[i]
    end
    return profile.pveColumnOrder
end

ns.PvEUI.GetPvEDawnCrestColumnDefinitions = GetPvEDawnCrestColumnDefinitions
ns.PvEUI.EnsureVaultButtonColumnsForPvE = EnsureVaultButtonColumnsForPvE
ns.PvEUI.EnsurePvEExtraVisibleColumns = EnsurePvEExtraVisibleColumns
ns.PvEUI.GetPvEDefaultColumnKeyOrder = GetPvEDefaultColumnKeyOrder
ns.PvEUI.EnsurePvEColumnOrder = EnsurePvEColumnOrder

local function IsPvEInlineColumnKeyVisible(key, profile, vc, ex)
    if not key or type(key) ~= "string" then return false end
    if key:find("^crest_") then
        return ex[key] ~= false
    end
    if key == "coffer_shards" then return ex.coffer_shards ~= false end
    if key == "restored_key" then return ex.restored_key ~= false end
    if key == "shard_of_dundun" then return ex.shard_of_dundun ~= false end
    if key == "voidcore" then return vc.voidcore ~= false end
    if key == "manaflux" then return vc.manaflux == true end
    if key == "slot1" then return vc.raids ~= false end
    if key == "slot2" then return vc.mythicPlus ~= false end
    if key == "slot3" then return vc.world ~= false end
    if key == "bountiful" then return vc.bounty ~= false end
    if key == "vault_status" then return vc.status ~= false end
    return false
end

local function BuildPvEColumnKeySequence(profile)
    local seq = {}
    if not profile then return seq end
    local vc = EnsureVaultButtonColumnsForPvE(profile)
    local ex = EnsurePvEExtraVisibleColumns(profile)
    local order = EnsurePvEColumnOrder(profile)
    for i = 1, #order do
        local key = order[i]
        if IsPvEInlineColumnKeyVisible(key, profile, vc, ex) then
            seq[#seq + 1] = key
        end
    end
    return seq
end

ns.PvEUI.BuildPvEColumnKeySequence = BuildPvEColumnKeySequence
ns.PvEUI.IsPvEInlineColumnKeyVisible = IsPvEInlineColumnKeyVisible

local function PveBuildStructureColSig(profile)
    if not profile then return "" end
    local PUI = ns.PvEUI
    local ensureEx = PUI and PUI.EnsurePvEExtraVisibleColumns
    local ensureVc = PUI and PUI.EnsureVaultButtonColumnsForPvE
    local buildSeq = PUI and PUI.BuildPvEColumnKeySequence
    if not ensureEx or not ensureVc or not buildSeq then return "" end
    local ex = ensureEx(profile)
    local vc = ensureVc(profile)
    local keys = {}
    local crests = GetPvEDawnCrestColumnDefinitions()
    for i = 1, #crests do
        local ck = "crest_" .. tostring(crests[i].id)
        if ex[ck] ~= false then keys[#keys + 1] = ck end
    end
    if ex.coffer_shards ~= false then keys[#keys + 1] = "coffer_shards" end
    if ex.restored_key ~= false then keys[#keys + 1] = "restored_key" end
    if ex.shard_of_dundun ~= false then keys[#keys + 1] = "shard_of_dundun" end
    if vc.voidcore ~= false then keys[#keys + 1] = "voidcore" end
    if vc.manaflux == true then keys[#keys + 1] = "manaflux" end
    if vc.raids ~= false then keys[#keys + 1] = "slot1" end
    if vc.mythicPlus ~= false then keys[#keys + 1] = "slot2" end
    if vc.world ~= false then keys[#keys + 1] = "slot3" end
    if vc.bounty ~= false then keys[#keys + 1] = "bountiful" end
    if vc.status ~= false then keys[#keys + 1] = "vault_status" end
    keys = PveOrderColumnKeysBySequence(keys, buildSeq(profile))
    return table.concat(keys, "\1")
end

local function PvE_GetGapAfterColumnKey(leftKey, visibleKeySet)
    if leftKey == "slot1" or leftKey == "slot2" then return PVE_VAULT_CLUSTER_GAP end
    if leftKey == "slot3" then return PVE_KEY_TO_VAULT_GAP end
    if leftKey == "manaflux" then return PVE_KEY_TO_VAULT_GAP end
    if leftKey == "voidcore" and (not visibleKeySet.manaflux) then return PVE_KEY_TO_VAULT_GAP end
    if leftKey == "shard_of_dundun" and (not visibleKeySet.voidcore) and (not visibleKeySet.manaflux) then
        return PVE_KEY_TO_VAULT_GAP
    end
    if leftKey == "restored_key" and (not visibleKeySet.shard_of_dundun) and (not visibleKeySet.voidcore) and (not visibleKeySet.manaflux) then
        return PVE_KEY_TO_VAULT_GAP
    end
    return PVE_COL_SPACING
end

--- Center X of each gap between inline PvE columns (parent-local).
local function BuildPvEInlineColumnDividerXs(startX, columns, gapAfterIndex)
    local xs = {}
    if not startX or not columns or #columns < 2 then return xs end
    local x = startX
    for ci = 1, #columns - 1 do
        local col = columns[ci]
        local gap = (gapAfterIndex and gapAfterIndex(ci)) or PVE_COL_SPACING
        xs[#xs + 1] = x + col.width + gap * 0.5
        x = x + col.width + gap
    end
    return xs
end

-- Toolbar controls: PvEUI_ColumnPicker.lua (Columns, Hide, Current toggle)
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
    local measureNameW = ns.PvE_MeasureStackedNameColumnWidth
    if FM and #characters > 0 and measureNameW then
        local tempMeasure = FM:CreateFontString(UIParent, "body", "OVERLAY")
        tempMeasure:Hide()
        for i = 1, #characters do
            local c = characters[i]
            local realmStr = ns.Utilities and ns.Utilities:FormatRealmName(c.realm) or c.realm or ""
            local w = measureNameW(tempMeasure, c.name or "Unknown", realmStr)
            if w > maxNameRealmWidth then maxNameRealmWidth = w end
        end
        tempMeasure:SetParent(nil)
    end
    local nameWidth = (ns.PvE_ResolveNameColumnWidth and ns.PvE_ResolveNameColumnWidth(maxNameRealmWidth))
        or math.max(100, math.ceil(maxNameRealmWidth) + 4)
    local prefixW = (ns.PvE_ComputeCharacterRowPrefixToGoldPx and ns.PvE_ComputeCharacterRowPrefixToGoldPx(nameWidth)) or 400
    local tabSide = (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin()) or SIDE_MARGIN
    if not profile then return 2 * tabSide + prefixW + PVE_COL_RIGHT_MARGIN end
    local columnSeq = BuildPvEColumnKeySequence(profile)
    local visibleKeySet = {}
    for i = 1, #columnSeq do
        visibleKeySet[columnSeq[i]] = true
    end
    local vb = profile.vaultButton or {}
    local vaultTrackColW = (ns.ResolveVaultTrackerColumnWidth
        and ns.ResolveVaultTrackerColumnWidth(vb.showRewardProgress == true, vb.showRewardItemLevel == true))
        or ((vb.showRewardProgress and vb.showRewardItemLevel) and PVE_VAULT_COL_REWARD_PROGRESS_W)
        or (vb.showRewardProgress and PVE_VAULT_COL_PROGRESS_W)
        or (vb.showRewardItemLevel and PVE_VAULT_COL_ILVL_W)
        or PVE_VAULT_COL_W

    local widthByKey = {
        coffer_shards = PVE_COFFER_COL_W,
        restored_key = PVE_KEY_COL_W,
        shard_of_dundun = PVE_DUNDUN_COL_W,
        voidcore = PVE_VOIDCORE_COL_W,
        manaflux = PVE_MANAFLUX_COL_W,
        slot1 = vaultTrackColW,
        slot2 = vaultTrackColW,
        slot3 = vaultTrackColW,
        bountiful = PVE_BOUNTIFUL_COL_W,
        vault_status = PVE_STATUS_COL_W,
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
    return 2 * tabSide + prefixW + inlineTotal
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
        expandedStates[key] = defaultState == true
    end
    return expandedStates[key] == true
end

function ns.PvE_ResetSessionExpandState()
    wipe(expandedStates)
    if WarbandNexus then
        WarbandNexus.pveExpandAllActive = false
    end
end

-- PvE event refresh is centralized in UI.lua SchedulePopulateContent (WN_PVE_UPDATED).

-- Great Vault grid + track column helpers: Modules/UI/PvEUI_VaultGrid.lua (ops-037).
local PvE_FormatVaultTrackColumn = ns.PvEUI and ns.PvEUI.FormatVaultTrackColumn
local PvE_GetCanonicalKeyForChar = ns.PvEUI and ns.PvEUI.GetCanonicalKeyForChar
assert(PvE_FormatVaultTrackColumn, "PvEUI: PvEUI_VaultGrid.lua must load before PvEUI.lua")

--- Viewport width for expanded PvE detail cards (row width / scroll viewport — not min scrollChild width).
function ns.PvEUI_ResolveExpandedDetailWidth(charDetailContent, mainFrame, scrollParent)
    if charDetailContent then
        local left = charDetailContent:GetLeft()
        local right = charDetailContent:GetRight()
        if left and right and right > left then
            return right - left
        end
        local w = charDetailContent:GetWidth() or 0
        if w > 80 then
            return w
        end
    end
    local mf = mainFrame or (WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame)
    if ns.UI_GetMainTabViewportWidth and mf then
        local vw = ns.UI_GetMainTabViewportWidth(mf)
        if vw and vw > 80 then
            return math.max(200, vw - 20)
        end
    end
    local scroll = mf and mf.scroll
    if scroll then
        local vw = scroll:GetWidth()
        if vw and vw > 80 then
            return math.max(200, vw - 20)
        end
    end
    return 600
end

local function PvEUI_WipeExpandedDetailSurface(charDetailContent)
    if not charDetailContent then return end
    local bin = ns.UI_RecycleBin
    local children = { charDetailContent:GetChildren() }
    for i = 1, #children do
        local ch = children[i]
        ch:Hide()
        ch:ClearAllPoints()
        -- SetParent(nil) keeps the frame alive but unreachable; park in the
        -- recycle bin like every other teardown path (frames are never GC'd).
        if bin then ch:SetParent(bin) else ch:SetParent(nil) end
    end
    charDetailContent._pveCardContainer = nil
end

local function PvEUI_ExpandedDetailHasCards(charDetailContent)
    local cc = charDetailContent and charDetailContent._pveCardContainer
    if not cc then return false end
    local kids = { cc:GetChildren() }
    return #kids > 0
end

--- Resolve expanded detail height when cards already exist (skip full rebuild).
local function PvEUI_MeasureExpandedDetailHeight(charDetailContent)
    if not charDetailContent then return 0.1 end
    local stored = charDetailContent._wnSectionFullH
    if stored and stored >= 2 then return stored end
    local cc = charDetailContent._pveCardContainer
    if cc then
        local ch = cc:GetHeight()
        if ch and ch >= 2 then return ch end
    end
    local fh = charDetailContent:GetHeight()
    if fh and fh >= 2 then return fh end
    return (stored and stored > 0.1) and stored or 200
end

--- Populates expanded PvE per-character detail (M+, keystone, vault grid).
--- Extracted from DrawPvEProgress to avoid Lua 5.1 "more than 60 upvalues" on nested closures.
local function PvEUI_PopulateExpandedCharacterDetail(self, parent, charDetailContent, charExpandKey, charKey, pve, pveData, isCurrentChar)
            if not charDetailContent then return end
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            local bodyW = ns.PvEUI_ResolveExpandedDetailWidth(charDetailContent, mf, parent)
            if charDetailContent._wnPopulateKey == charExpandKey
                and charDetailContent._wnPopulateBodyW
                and math.abs(charDetailContent._wnPopulateBodyW - bodyW) < 4
                and PvEUI_ExpandedDetailHasCards(charDetailContent) then
                charDetailContent._wnSectionFullH = PvEUI_MeasureExpandedDetailHeight(charDetailContent)
                return
            end
            PvEUI_WipeExpandedDetailSurface(charDetailContent)
            charDetailContent._wnPopulateKey = charExpandKey
            charDetailContent._wnPopulateBodyW = bodyW

            local cardContainer = ns.UI.Factory:CreateContainer(charDetailContent)
            charDetailContent._pveCardContainer = cardContainer
            cardContainer:SetPoint("TOPLEFT", charDetailContent, "TOPLEFT", 0, 0)
            cardContainer:SetPoint("TOPRIGHT", charDetailContent, "TOPRIGHT", 0, 0)

            -- Calculate responsive card widths (pixel-snapped)
            -- Order: Overall Score (35%) → Keystone+Affixes (35%) → Vault (30%)
            local PixelSnap = ns.PixelSnap or function(v) return v end
            local totalWidth = PixelSnap(bodyW)
            -- Vault card: 4 equal columns (Label + 3 slots), each needs room for "Dungeons" + icon
            local card3Width = PixelSnap(math.max(360, totalWidth * 0.40))  -- Vault (min 360px)
            local remaining  = totalWidth - card3Width
            local card1Width = PixelSnap(remaining * 0.48)  -- Overall Score (M+ dungeons)
            local card2Width = PixelSnap(remaining - card1Width)  -- Keystone + Affixes
            local cardSpacing = 5
            
            -- Card height will be calculated from vault card grid (with fallback)
            local cardHeight = 200  -- Default fallback height
            
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
                scoreColor = PveMplusScoreColor500()
            else
                scoreColor = "|cff9d9d9d"
            end
            
            local overallScoreLabel = GetLocalizedText("OVERALL_SCORE_LABEL", "Overall Score:")
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
                            dScoreColor = PveMplusScoreColor500()
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
                                local bestKeyLabel = GetLocalizedText("VAULT_BEST_KEY", "Best Key:")
                                table.insert(tooltipLines, {
                                    text = string.format("%s |cffffcc00+%d|r", bestKeyLabel, dungeon.bestLevel),
                                    color = {0.9, 0.9, 0.9}
                                })
                                local scoreLabel = GetLocalizedText("VAULT_SCORE", "Score:")
                                table.insert(tooltipLines, {
                                    text = string.format("%s %s%s|r", scoreLabel, PveBrightHex(), FormatNumber(dungeon.score or 0)),
                                    color = {0.9, 0.9, 0.9}
                                })
                            else
                                local notCompletedLabel = GetLocalizedText("NOT_COMPLETED_SEASON", "Not completed this season")
                                table.insert(tooltipLines, {
                                    text = "|cff888888" .. notCompletedLabel .. "|r",
                                    color = {0.6, 0.6, 0.6}
                                })
                            end
                            ShowTooltip(self, {
                                type = "custom",
                                icon = dungeon.texture or "Interface\\Icons\\INV_Misc_QuestionMark",
                                title = dungeon.name or (GetLocalizedText("VAULT_DUNGEON", "Dungeon")),
                                lines = tooltipLines,
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
                local noDataLabel = GetLocalizedText("NO_DATA", "No data")
                noData:SetText("|cff666666" .. noDataLabel .. "|r")
                mplusNeededH = math.max(baseCardHeight, mplusY + 40)
            end
            
            mplusCard:SetHeight(mplusNeededH)
            mplusCard:Show()
            
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
            local keystoneLabel = GetLocalizedText("KEYSTONE", "Keystone")
            keystoneTitle:SetText(PveBrightHex() .. keystoneLabel .. "|r")
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
                    nameText:SetText(mapName or (GetLocalizedText("KEYSTONE", "Keystone")))
                else
                    local noKeyText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                    noKeyText:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -20)
                    local noKeyLabel = GetLocalizedText("NO_KEY", "No Key")
                    noKeyText:SetText("|cff888888" .. noKeyLabel .. "|r")
                    noKeyText:SetJustifyH("CENTER")
                end
            else
                local noKeyText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                noKeyText:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -20)
                local noKeyLabel = GetLocalizedText("NO_KEY", "No Key")
                noKeyText:SetText("|cff888888" .. noKeyLabel .. "|r")
                noKeyText:SetJustifyH("CENTER")
            end
            
            -- Affixes (Right Column)
            local col2X = col1X + topColumnWidth + columnSpacing
            local col2Y = col1Y
            local summaryAffixBottom = col2Y + 82
            
            local affixesTitle = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
            affixesTitle:SetPoint("TOP", summaryCard, "TOPLEFT", col2X + topColumnWidth / 2, -col2Y)
            local affixesLabel = GetLocalizedText("AFFIXES", "Affixes")
            affixesTitle:SetText(PveBrightHex() .. affixesLabel .. "|r")
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
                                        title = name or (GetLocalizedText("AFFIX_TITLE_FALLBACK", "Affix")),
                                        description = description,
                                        lines = {},
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
                local noAffixesLabel = GetLocalizedText("NO_AFFIXES", "No Affixes")
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
                local currencyName = currencyEntry and currencyEntry.name or (GetLocalizedText("TAB_CURRENCY", "Currency"))

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
                    -- Current/Weekly toolbar + Shift invert (see FormatHelpers).
                    ns.UI_BindSeasonProgressAmount(amountText, currencyEntry, { pveDisplayMode = true })
                elseif ns.UI_FormatSeasonProgressCurrencyLine then
                    amountText:SetText(ns.UI_FormatSeasonProgressCurrencyLine(currencyEntry))
                else
                    local amtColor = PveBrightHex()
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
            
            local vaultCard = CreateCard(cardContainer, baseCardHeight)
            vaultCard:SetPoint("TOPLEFT", PixelSnap(card1Width + card2Width), 0)
            local baseCardWidth = card3Width
            
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
        
        -- Create a NEW table on each render (don't reuse old data)
        local vaultActivities = {}
        
        -- Flatten vault activities (raids, mythicPlus, pvp, world) into single array.
        -- Skip if isPostReset: data is from last week after reset — show fresh 0 progress.
        -- hasUnclaimedRewards still shows the vault chest as ready to claim separately.
        if vaultActivitiesData and not vaultActivitiesData.isPostReset then
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
                -- Use locale-independent internal keys for vaultByType.
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
            
            vaultCard:SetHeight(baseCardHeight)
            vaultCard:SetWidth(baseCardWidth)
            cardHeight = baseCardHeight

            local detailGen = ns.PvEUI._detailPaintGen or 0
            charDetailContent._pveDetailGen = detailGen
            local populateKey = charExpandKey
            local vaultPaintOpt = {
                baseCardWidth = baseCardWidth,
                baseCardHeight = baseCardHeight,
                vaultByType = vaultByType,
                pve = pve,
                vaultActivitiesData = vaultActivitiesData,
                isCurrentChar = isCurrentChar,
            }
            local function finishDeferredVaultGrid()
                if not charDetailContent or charDetailContent._wnPopulateKey ~= populateKey then return end
                if charDetailContent._pveDetailGen ~= detailGen then return end
                local ok, paintedH = pcall(self.PaintPvEVaultGridOnCard, self, vaultCard, vaultPaintOpt)
                if not ok then
                    if ns.DebugPrint then
                        ns.DebugPrint("PvE vault grid paint failed:", paintedH)
                    end
                    paintedH = baseCardHeight
                else
                    paintedH = paintedH or baseCardHeight
                end
                cardHeight = paintedH
                local vaultPaintedH = cardHeight
                local mH = mplusCard:GetHeight() or baseCardHeight
                local sH = summaryCard:GetHeight() or baseCardHeight
                local vH = vaultCard:GetHeight() or vaultPaintedH
                local unifiedRowH = math.max(160, mH, sH, vH)
                mplusCard:SetHeight(unifiedRowH)
                summaryCard:SetHeight(unifiedRowH)
                vaultCard:SetHeight(unifiedRowH)
                cardContainer:SetHeight(unifiedRowH)
                local layoutH = math.max(0.1, unifiedRowH)
                charDetailContent._wnSectionFullH = layoutH
                charDetailContent:SetHeight(layoutH)
                charDetailContent:Show()
                if charDetailContent._pveOnLayoutChanged then
                    charDetailContent._pveOnLayoutChanged(layoutH)
                end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, finishDeferredVaultGrid)
            else
                finishDeferredVaultGrid()
            end
        else
            -- No vault data: Still set card dimensions so it's visible
            vaultCard:SetHeight(baseCardHeight)
            vaultCard:SetWidth(baseCardWidth)
            
            local noVault = FontManager:CreateFontString(vaultCard, "small", "OVERLAY")
            noVault:SetPoint("CENTER", vaultCard, "CENTER", 0, 0)
            local noVaultLabel = GetLocalizedText("NO_VAULT_DATA", "No vault data")
            noVault:SetText("|cff666666" .. noVaultLabel .. "|r")
        end
        
        vaultCard:Show()

            -- Placeholder unified height until deferred vault grid finishes (if any).
            local vaultPaintedH = cardHeight or baseCardHeight
            local mH = mplusCard:GetHeight() or baseCardHeight
            local sH = summaryCard:GetHeight() or baseCardHeight
            local vH = vaultCard:GetHeight() or vaultPaintedH
            local unifiedRowH = math.max(160, mH, sH, vH)
            mplusCard:SetHeight(unifiedRowH)
            summaryCard:SetHeight(unifiedRowH)
            vaultCard:SetHeight(unifiedRowH)
            cardContainer:SetHeight(unifiedRowH)
            local layoutH = math.max(0.1, unifiedRowH)
            charDetailContent._wnSectionFullH = layoutH
            charDetailContent:SetHeight(layoutH)
            charDetailContent:Show()
            if charDetailContent._pveOnLayoutChanged then
                charDetailContent._pveOnLayoutChanged(layoutH)
            end
end
ns.PvEUI_PopulateExpandedCharacterDetail = PvEUI_PopulateExpandedCharacterDetail

--- Group id from secKey "pve_grp:<id>". Prefix is 8 chars ("pve_grp:"); using sub(10) strips the first id character and breaks lookups.
local function PveGroupIdFromSectionSecKey(secKey)
    if type(secKey) ~= "string" then return nil end
    return secKey:match("^pve_grp:(.+)$")
end

--- One Favorites / custom / Characters collapsible block on the PvE scroll child (ProfessionsUI-style shell; rows painted separately).
--- @param layoutTailFrame nil or frame to stack below (last character detail or previous section body)
--- @return sectionContent frame to parent per-character PvE rows under
local function PvEUI_CreatePvETabSectionShell(addon, scrollParent, profile, opts)
    local chars = opts.chars
    local headerLabel = opts.headerLabel
    local sectionUiKey = opts.sectionUiKey -- profile.ui key when not using characterGroupExpanded
    local defaultExpanded = opts.defaultExpanded == true
    local headerAtlas = opts.headerAtlas
    local visualOpts = opts.visualOpts
    local layoutTailFrame = opts.layoutTailFrame
    local totalLH = opts.totalLH
    local scrollFrameRef = opts.scrollFrameRef
    local yTop = opts.yTop
    local SIDE_MARGIN0 = opts.sideMargin or SIDE_MARGIN
    local stackW = opts.stackWidth or math.max(1, (scrollParent:GetWidth() or 400) - 2 * SIDE_MARGIN0)

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
    local headerVisualOpts = BuildCollapsibleSectionOpts({
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
        -- Do not resize scrollParent from section height changes (same class of bug as per-character rows).
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
    headerVisualOpts.sectionStackWidth = stackW

    local expandKey = opts.expandKey
    if not expandKey then
        if visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId then
            -- Same identity as Characters tab custom sections (SharedWidgets / roster parity).
            expandKey = "cgrp_" .. tostring(visualOpts.groupId)
        else
            expandKey = sectionUiKey or "pveSection"
        end
    end

    scrollParent._pveSectionShellOrder = scrollParent._pveSectionShellOrder or {}
    local shellOrderDup = false
    for soi = 1, #scrollParent._pveSectionShellOrder do
        if scrollParent._pveSectionShellOrder[soi] == expandKey then
            shellOrderDup = true
            break
        end
    end
    if not shellOrderDup then
        scrollParent._pveSectionShellOrder[#scrollParent._pveSectionShellOrder + 1] = expandKey
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
                    sectionContent:SetHeight(math.max(0.1, sectionContent._wnSectionFullH or 0.1))
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
    if header.SetWidth then
        header:SetWidth(math.max(1, stackW))
    end
    if layoutTailFrame then
        header:SetPoint("TOPLEFT", layoutTailFrame, "BOTTOMLEFT", 0, -4)
    else
        header:SetPoint("TOPLEFT", scrollParent, "TOPLEFT", SIDE_MARGIN0, -yTop)
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
        sectionContent = ns.UI.Factory:CreateContainer(scrollParent, math.max(1, stackW), 1, false)
    else
        sectionContent = CreateFrame("Frame", nil, scrollParent)
        sectionContent:SetSize(math.max(1, stackW), 1)
    end
    sectionContent:ClearAllPoints()
    sectionContent:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    if sectionContent.SetWidth then
        sectionContent:SetWidth(math.max(1, stackW))
    end
    sectionContent:SetHeight(0.1)
    sectionContent._wnSectionFullH = 0
    sectionContent._pveRunningH = 0
    header._wnKeepOnTabSwitch = true
    sectionContent._wnKeepOnTabSwitch = true
    _pveDrawPool.sectionShells = _pveDrawPool.sectionShells or {}
    _pveDrawPool.sectionShells[expandKey] = { header = header, body = sectionContent }

    if isExpanded then
        sectionContent:Show()
        sectionContent:SetHeight(math.max(0.1, sectionContent._wnSectionFullH or 0.1))
    else
        sectionContent:Hide()
        sectionContent:SetHeight(0.1)
    end

    return sectionContent
end

-- DRAW PVE PROGRESS (Great Vault, Lockouts, M+)

ns.PvEUI = ns.PvEUI or {}
ns.PvEUI.BuildPvEColumnKeySequence = BuildPvEColumnKeySequence
ns.PvEUI.EnsurePvEColumnOrder = EnsurePvEColumnOrder
--- Cancel in-flight chunked PvE row paint (tab switch).
function ns.PvEUI.AbortChunkedPaint()
    ns.PvEUI._paintDrawGen = (ns.PvEUI._paintDrawGen or 0) + 1
    ns.PvEUI._detailPaintGen = (ns.PvEUI._detailPaintGen or 0) + 1
end
ns.PvEUI.PAINT_CHUNK_SIZE = 2
ns.PvEUI.PAINT_CHUNK_MIN = 1
ns.PvEUI.PVE_VIRTUAL_ROW_MIN = 6

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
        BuildCollapsibleSectionOpts = BuildCollapsibleSectionOpts,
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
        PvE_ComputeInlineColumnsStartPx = ns.PvE_ComputeInlineColumnsStartPx,
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
        PVE_DUNDUN_COL_W = PVE_DUNDUN_COL_W,
        PVE_VOIDCORE_COL_W = PVE_VOIDCORE_COL_W,
        PVE_MANAFLUX_COL_W = PVE_MANAFLUX_COL_W,
        PVE_DUNDUN_ID = PVE_DUNDUN_ID,
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
        PvEAcquireCharRowFrames = PvEAcquireCharRowFrames,
        PvE_GetVaultStatusCached = PvE_GetVaultStatusCached,
        PvE_BuildColumnLayoutSig = PvE_BuildColumnLayoutSig,
        PvE_ApplyCachedColumnWidths = PvE_ApplyCachedColumnWidths,
        PvE_SaveColumnLayoutCache = PvE_SaveColumnLayoutCache,
        UI_SyncGridColumnDividers = ns.UI_SyncGridColumnDividers,
        BuildPvEInlineColumnDividerXs = BuildPvEInlineColumnDividerXs,
        GetPvECachedCurrencyDisplay = GetPvECachedCurrencyDisplay,
        EnsureVaultButtonColumnsForPvE = EnsureVaultButtonColumnsForPvE,
        EnsurePvEExtraVisibleColumns = EnsurePvEExtraVisibleColumns,
        ResolvePveDelveCurrencyColumns = ResolvePveDelveCurrencyColumns,
        GetTrovehunterBountyColumnIcon = GetTrovehunterBountyColumnIcon,
        PvE_AttachPvEColumnsButton = ns.PvE_AttachPvEColumnsButton,
        PvE_AttachHideLevelFilterButton = ns.PvE_AttachHideLevelFilterButton,
        PvE_GetCanonicalKeyForChar = PvE_GetCanonicalKeyForChar,
        CompareCharNameLower = CompareCharNameLower,
        SafeLower = SafeLower,
        expandedStates = expandedStates,
        IsExpanded = IsExpanded,
        PvEUI_CreatePvETabSectionShell = PvEUI_CreatePvETabSectionShell,
        PvEUI_PopulateExpandedCharacterDetail = ns.PvEUI_PopulateExpandedCharacterDetail,
        PvE_FormatVaultTrackColumn = PvE_FormatVaultTrackColumn,
        BindForwardScrollWheel = BindForwardScrollWheel,
        ColumnOrder = ColumnOrder,
        BuildPvEColumnKeySequence = BuildPvEColumnKeySequence,
        EnsurePvEColumnOrder = EnsurePvEColumnOrder,
        GetPvEDefaultColumnKeyOrder = GetPvEDefaultColumnKeyOrder,
    }
end

--- Inner stack width after symmetric tab side insets (header/sections anchor at contentSide).
local function PvEStackBodyWidth(scrollPaintW, contentSide)
    local side = contentSide or SIDE_MARGIN
    return math.max(1, (tonumber(scrollPaintW) or 1) - 2 * side)
end

local function PvEUI_DrawPvEProgressBody(self, parent, L, opts)
    opts = opts or {}
    if not L or not L.EnsureVaultButtonColumnsForPvE or not L.EnsurePvEExtraVisibleColumns then
        return parent and (parent:GetHeight() or 1) or 0
    end
    local bodyOnly = opts.bodyOnly == true
    local mf = L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame
    local chrome, metrics, fixedHeader, headerParent, headerYOffset, contentSide, stackWidth, scrollTopY

    if not bodyOnly then
        ns.PvE_ClearVaultStatusScratch()
        parent._pveChunkPaintPending = nil

        chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
        metrics = (chrome and chrome.metrics) or (ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf))
        fixedHeader = mf and mf.fixedHeader
        headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
        headerYOffset = (chrome and chrome.yOffset) or 0
        contentSide = (chrome and chrome.side) or (metrics and metrics.sideMargin) or L.SIDE_MARGIN
        stackWidth = (metrics and metrics.bodyWidth and metrics.bodyWidth > 0) and metrics.bodyWidth
            or (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent))
            or math.max(200, (parent:GetWidth() or 600) - contentSide * 2)
        parent._wnPveContentSide = contentSide
        scrollTopY = (ns.UI_GetTabColumnHeaderScrollTop and ns.UI_GetTabColumnHeaderScrollTop()) or 0
    else
        contentSide = parent._wnPveContentSide or L.SIDE_MARGIN
        scrollTopY = opts.scrollTopY or ((ns.UI_GetTabColumnHeaderScrollTop and ns.UI_GetTabColumnHeaderScrollTop()) or 0)
        local mfBody = L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame
        metrics = mfBody and ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mfBody)
        stackWidth = (metrics and metrics.bodyWidth and metrics.bodyWidth > 0) and metrics.bodyWidth
            or parent._wnPveStackWidth
            or (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mfBody, parent))
            or math.max(200, (parent:GetWidth() or 600) - contentSide * 2)
    end
    
    if not bodyOnly then
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "PvECache"
        if self.db.global.pveCache and self.db.global.pveCache.version then
            local cacheVersion = self.db.global.pveCache.version or "unknown"
            dataSource = "PvECache v" .. cacheVersion
        end
        parent.dbVersionBadge = L.CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Hide empty state card (will be shown again if needed)
    L.HideEmptyStateCard(parent, "pve")
    -- Prior build used _wnPveTabContentHost; discard any orphan so scrollChild teardown stays one-level.
    local stalePveHost = parent._wnPveTabContentHost
    if stalePveHost then
        parent._wnPveTabContentHost = nil
        local rb = ns.UI_RecycleBin
        if rb and stalePveHost.SetParent then
            stalePveHost:Hide()
            stalePveHost:SetParent(rb)
        end
    end
    
    local charKey = (L.ns.UI_GetSubsidiaryCharKey and L.ns.UI_GetSubsidiaryCharKey())
        or (L.ns.CharacterService and L.ns.CharacterService.ResolveSubsidiaryCharacterKey and L.ns.CharacterService:ResolveSubsidiaryCharacterKey(L.WarbandNexus, nil))
    local pveData = self:GetPvEData(charKey)
    
    -- Check multiple data completeness signals, not just keystone
    local needsRefresh = false
    if not pveData or not pveData.keystone then
        needsRefresh = true
    elseif pveData.vaultActivities and not pveData.vaultActivities.isPostReset then
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
            -- Never run UpdatePvEData synchronously inside PopulateContent: heavy API + DB work
            -- caused multi-second frame spikes; pool teardown on tab switch then compounded the hitch.
            local deferAddon = self
            C_Timer.After(0, function()
                if not deferAddon or not deferAddon.UpdatePvEData then return end
                local mf = L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame
                if not mf or not mf:IsShown() or mf.currentTab ~= "pve" then return end
                -- VaultScanner owns OnUIInteract at login; avoid re-poking when tab refresh runs mid-session.
                if C_WeeklyRewards and C_WeeklyRewards.OnUIInteract then
                    local scannerReady = ns.VaultScanner and ns.VaultScanner.IsInitialized and ns.VaultScanner.IsInitialized()
                    if not scannerReady then
                        C_WeeklyRewards.OnUIInteract()
                    end
                end
                deferAddon:UpdatePvEData()
            end)
            C_Timer.After(3, function()
                if not deferAddon or not deferAddon.UpdatePvEData then return end
                local mf = L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame
                if not mf or not mf:IsShown() or mf.currentTab ~= "pve" then return end
                deferAddon:UpdatePvEData()
            end)
        end
    end
    end -- not bodyOnly (badge / needsRefresh prelude)

    local profile = self.db and self.db.profile
    local sortBtn
    local titleCard

    if not bodyOnly then
    local r, g, b = L.COLORS.accent[1], L.COLORS.accent[2], L.COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleTextContent = "|cff" .. hexColor .. (GetLocalizedText("PVE_TITLE", "PvE Progress")) .. "|r"
    local subtitleTextContent = GetLocalizedText("PVE_SUBTITLE", "Great Vault, Raid Lockouts & Mythic+ across your Warband")
    local tm = L.ns.UI_GetTitleCardToolbarMetrics and L.ns.UI_GetTitleCardToolbarMetrics() or {}
    local hdrGapPve = tm.gap or (L.GetLayout().HEADER_TOOLBAR_CONTROL_GAP or 8)
    local pveToolbarReserve = (L.ns.UI_ComputeTitleToolbarReserve and L.ns.UI_ComputeTitleToolbarReserve({
        168,
        tm.filterW or 96,
        tm.columnsW or 86,
        tm.toggleW or 88,
        tm.hideW or 84,
    })) or (640 + hdrGapPve)

    local hdrCache = mf and mf._pveFixedHeaderCache
    local headerDone = false
    if hdrCache and hdrCache.titleCard then
        headerYOffset = RepositionPveFixedHeader(mf, hdrCache, headerParent, chrome, headerYOffset, contentSide, parent)
        if ns.UI_CommitTabFixedHeader then
            ns.UI_CommitTabFixedHeader(mf, headerYOffset)
        elseif fixedHeader then
            fixedHeader:SetHeight(headerYOffset)
        end
        titleCard = hdrCache.titleCard
        sortBtn = hdrCache.sortBtn
        if ns.PvE_RefreshCurrencyDisplayToggleChrome and WarbandNexus._wnPvECurrencyViewToggleBtn then
            ns.PvE_RefreshCurrencyDisplayToggleChrome(
                WarbandNexus._wnPvECurrencyViewToggleBtn,
                WarbandNexus._wnPvECurrencyViewToggleLbl
            )
        end
        headerDone = true
    end

    if not headerDone then
    titleCard = select(1, L.ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "pve",
        titleText = titleTextContent,
        subtitleText = subtitleTextContent,
        textRightInset = pveToolbarReserve,
    }))
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    end
    
    -- Weekly reset timer (re-anchored left of toolbar buttons after they are placed)
    local CreateResetTimer = L.ns.UI_CreateResetTimer
    local titleEdgeInset = tm.edgeInset or 0
    local hdrGap = tm.gap or 8
    local resetTimer = CreateResetTimer(
        titleCard,
        "TOPRIGHT",
        0,
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
    if resetTimer and resetTimer.container then
        resetTimer.container:ClearAllPoints()
    end
    
    -- Sort + section filter: buttons right-aligned (rightmost first), reset sits left of the group
    local toolbarLeft = titleCard
    local sortOptions = (L.ns.UI_BuildCharacterSortOptions and L.ns.UI_BuildCharacterSortOptions())
        or {}
    if not self.db.profile.pveSort then self.db.profile.pveSort = {} end
    if L.ns.UI_CreateCharacterTabAdvancedFilterButton and L.ns.CharacterService and L.ns.CharacterService.EnsureCustomCharacterSectionsProfile then
        L.ns.CharacterService:EnsureCustomCharacterSectionsProfile(self.db.profile)
        if not self.db.profile.pveSectionFilter then self.db.profile.pveSectionFilter = { sectionKey = "all" } end
        sortBtn = L.ns.UI_CreateCharacterTabAdvancedFilterButton(titleCard, {
            sortOptions = sortOptions,
            dbSortTable = self.db.profile.pveSort,
            sortTabId = "pve",
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
            if L.ns.UI_AnchorTitleCardToolbarControl then
                L.ns.UI_AnchorTitleCardToolbarControl(sortBtn, titleCard, titleCard, "RIGHT", -titleEdgeInset)
            else
                sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleEdgeInset, 0)
            end
            toolbarLeft = sortBtn
        end
    elseif L.ns.UI_CreateCharacterSortDropdown then
        sortBtn = L.ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.pveSort, function()
            L.WarbandNexus:SendMessage(L.E.UI_MAIN_REFRESH_REQUESTED, { tab = "pve", skipCooldown = true })
        end, "pve")
        if L.ns.UI_AnchorTitleCardToolbarControl then
            L.ns.UI_AnchorTitleCardToolbarControl(sortBtn, titleCard, titleCard, "RIGHT", -titleEdgeInset)
        else
            sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleEdgeInset, 0)
        end
        toolbarLeft = sortBtn
    end

    if profile then
        if not profile.ui then profile.ui = {} end
        if profile.ui.pveFavoritesExpanded == nil then
            profile.ui.pveFavoritesExpanded = true
        end
        if profile.ui.pveCharactersExpanded == nil then
            profile.ui.pveCharactersExpanded = true
        end
    end

    -- Toolbar (right to left): Filter | Columns | Current | Hide | Reset
    local attachColumnsBtn = L.PvE_AttachPvEColumnsButton or (L.ns and L.ns.PvE_AttachPvEColumnsButton)
    if attachColumnsBtn and toolbarLeft then
        toolbarLeft = attachColumnsBtn(titleCard, toolbarLeft, self) or toolbarLeft
    end
    local attachCurrencyToggle = L.PvE_AttachCurrencyDisplayToggle or (L.ns and L.ns.PvE_AttachCurrencyDisplayToggle)
    if attachCurrencyToggle and toolbarLeft then
        toolbarLeft = attachCurrencyToggle(titleCard, toolbarLeft, self) or toolbarLeft
    end
    local attachHideBtn = L.PvE_AttachHideLevelFilterButton or (L.ns and L.ns.PvE_AttachHideLevelFilterButton)
    if attachHideBtn and toolbarLeft then
        toolbarLeft = attachHideBtn(titleCard, toolbarLeft, self) or toolbarLeft
    end

    if resetTimer and resetTimer.container and toolbarLeft then
        resetTimer.container:SetPoint("RIGHT", toolbarLeft, "LEFT", -hdrGap, 0)
    end

    if L.ns.UI_HideTitleCardExpandCollapseControls then
        L.ns.UI_HideTitleCardExpandCollapseControls(parent)
    end

    titleCard:Show()
    if ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight(), 0)
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) end
    else
        headerYOffset = headerYOffset + (titleCard:GetHeight() or 64)
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    end

    if mf then
        mf._pveFixedHeaderCache = {
            titleCard = titleCard,
            sortBtn = sortBtn,
            resetTimer = resetTimer and resetTimer.container,
            columnsBtn = WarbandNexus._wnPvEColumnPickerAnchorBtn,
        }
    end
    end -- not headerDone
    end -- not bodyOnly

    if bodyOnly then
        profile = profile or (self.db and self.db.profile)
    end

    local PVE_DAWNCRESTS = L.GetPvEDawnCrestColumnDefinitions()
    local PVE_RESTORED_KEY_FALLBACK_ID = 3089
    L.ResolvePveDelveCurrencyColumns(self)
    local PVE_SHARDS_ID = L._pveDelveCurrencyCache.shardsID
    local PVE_RESTORED_KEY_ID = L._pveDelveCurrencyCache.keyID
    local PVE_SHARDS_ICON = L._pveDelveCurrencyCache.shardsIcon or "Interface\\Icons\\INV_Misc_Gem_Variety_01"
    local PVE_RESTORED_KEY_ICON = L._pveDelveCurrencyCache.keyIcon or "Interface\\Icons\\INV_Misc_Key_13"
    if not PVE_RESTORED_KEY_ID then
        PVE_RESTORED_KEY_ID = PVE_RESTORED_KEY_FALLBACK_ID
    end

    profile = profile or (self.db and self.db.profile)
    local vaultCols, pveExtraCols, vbProfile, vaultTrackColW, PVE_COLUMNS
    local skipColumnBuild = bodyOnly and opts.columnDefs ~= nil
    if skipColumnBuild then
        PVE_COLUMNS = PveCopyColumnDefs(opts.columnDefs)
        vaultTrackColW = _pveDrawPool.vaultTrackColW or PVE_VAULT_COL_W
        vaultCols = L.EnsureVaultButtonColumnsForPvE(profile)
        pveExtraCols = L.EnsurePvEExtraVisibleColumns(profile)
        vbProfile = profile and profile.vaultButton or {}
    else
    local structureColSig = PveBuildStructureColSig(profile)
    local poolDefs = _pveDrawPool
    if poolDefs.columnDefsColSig == structureColSig and poolDefs.columnDefs then
        PVE_COLUMNS = PveCopyColumnDefs(poolDefs.columnDefs)
        vaultTrackColW = poolDefs.vaultTrackColW or PVE_VAULT_COL_W
        vaultCols = L.EnsureVaultButtonColumnsForPvE(profile)
        pveExtraCols = L.EnsurePvEExtraVisibleColumns(profile)
        vbProfile = profile and profile.vaultButton or {}
    else
    vaultCols = L.EnsureVaultButtonColumnsForPvE(profile)
    pveExtraCols = L.EnsurePvEExtraVisibleColumns(profile)
    vbProfile = profile and profile.vaultButton or {}
    vaultTrackColW = (L.ns.ResolveVaultTrackerColumnWidth
        and L.ns.ResolveVaultTrackerColumnWidth(vbProfile.showRewardProgress == true, vbProfile.showRewardItemLevel == true))
        or ((vbProfile.showRewardProgress and vbProfile.showRewardItemLevel) and PVE_VAULT_COL_REWARD_PROGRESS_W)
        or (vbProfile.showRewardProgress and PVE_VAULT_COL_PROGRESS_W)
        or (vbProfile.showRewardItemLevel and PVE_VAULT_COL_ILVL_W)
        or PVE_VAULT_COL_W
    PVE_COLUMNS = {}
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
    if pveExtraCols.shard_of_dundun ~= false then
        local dundunIcon = "Interface\\Icons\\INV_Misc_Gem_Variety_02"
        local dundunDisp = L.GetPvECachedCurrencyDisplay(L.PVE_DUNDUN_ID)
        if dundunDisp and dundunDisp.iconFileID then
            dundunIcon = dundunDisp.iconFileID
        end
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "shard_of_dundun",
            label = "",
            width = L.PVE_DUNDUN_COL_W,
            icon = dundunIcon,
            tooltipTitle = L.GetLocalizedText("PVE_COL_SHARD_OF_DUNDUN", "Shard of Dundun"),
            headerLabel = L.GetLocalizedText("PVE_COL_SHARD_OF_DUNDUN", "Shard of Dundun"),
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
            width = vaultTrackColW,
            icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
            tooltipTitle = GetLocalizedText("PVE_HEADER_RAIDS", "Raids"),
            headerLabel = L.GetLocalizedText("PVE_HEADER_RAID_SHORT", "Raid"),
        }
    end
    if vaultCols.mythicPlus ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "slot2",
            label = "",
            width = vaultTrackColW,
            icon = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
            tooltipTitle = GetLocalizedText("PVE_HEADER_DUNGEONS", "Dungeons"),
            headerLabel = L.GetLocalizedText("VAULT_DUNGEON", "Dungeon"),
        }
    end
    if vaultCols.world ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "slot3",
            label = "",
            width = vaultTrackColW,
            icon = "Interface\\Icons\\INV_Misc_Map_01",
            tooltipTitle = GetLocalizedText("VAULT_WORLD", "World"),
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
            tooltipTitle = GetLocalizedText("BOUNTIFUL_DELVE", "Trovehunter's Bounty"),
            headerLabel = L.GetLocalizedText("PVE_HEADER_MAP_SHORT", "Bounty"),
        }
    end
    -- Vault Status — same Ready/Slots Earned/Pending readout as the Vault Tracker quick window.
    if vaultCols.status ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "vault_status",
            label = "",
            width = L.PVE_STATUS_COL_W,
            icon = "Interface\\RaidFrame\\ReadyCheck-Ready",
            tooltipTitle = GetLocalizedText("PVE_COL_VAULT_STATUS", "Vault Status"),
            headerLabel = L.GetLocalizedText("PVE_HEADER_STATUS_SHORT", "Status"),
            headerIconIsAtlas = false,
        }
    end

    local pveColumnSeq = (L.BuildPvEColumnKeySequence or BuildPvEColumnKeySequence)(profile)
    local colOrderApi = L.ColumnOrder or ColumnOrder
    if colOrderApi and colOrderApi.SortColumnsByKeySequence then
        colOrderApi.SortColumnsByKeySequence(PVE_COLUMNS, pveColumnSeq)
    end
        poolDefs.columnDefsColSig = structureColSig
        poolDefs.columnDefs = PveCopyColumnDefs(PVE_COLUMNS)
        poolDefs.vaultTrackColW = vaultTrackColW
    end
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
        if key == "shard_of_dundun" and (not visiblePveColumnKeys.voidcore) and (not visiblePveColumnKeys.manaflux) then
            return L.PVE_KEY_TO_VAULT_GAP
        end
        if key == "restored_key" and (not visiblePveColumnKeys.shard_of_dundun) and (not visiblePveColumnKeys.voidcore) and (not visiblePveColumnKeys.manaflux) then
            return L.PVE_KEY_TO_VAULT_GAP
        end
        if key == "slot1" or key == "slot2" then return L.PVE_VAULT_CLUSTER_GAP end
        if key == "slot3" then return L.PVE_KEY_TO_VAULT_GAP end
        return L.PVE_COL_SPACING
    end

    local rosterSigFast = PveBuildFastRosterSig(self, profile)
    local drawSig = opts.drawSig or PveBuildFullDrawSig(self, profile, rosterSigFast, colSig)
    local rosterCount = tonumber(rosterSigFast:match("^(%d+)")) or 0

    if not bodyOnly then
        if not L.ns.Utilities:IsModuleEnabled("pve") then
            L.WarbandNexus._pveVaultTooltipCharsSnapshot = {}
            local CreateDisabledCard = L.ns.UI_CreateDisabledModuleCard
            local cardHeight = CreateDisabledCard(parent, scrollTopY, GetLocalizedText("PVE_TITLE", "PvE Progress"))
            return scrollTopY + cardHeight
        end

        local chr = _pveDrawPool.colHeaderRow
        if parent._pveBodyReady and parent._pveDrawSig == drawSig and chr and chr:GetParent() == parent then
            local contentSideCached = parent._wnPveContentSide or L.SIDE_MARGIN
            local mfCached = mf or (L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame)
            local metricsCached = mfCached and ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mfCached)
            local bodyW = (metricsCached and metricsCached.bodyWidth and metricsCached.bodyWidth > 0) and metricsCached.bodyWidth
                or parent._wnPveStackWidth
                or math.max(200, (parent:GetWidth() or 600) - contentSideCached * 2)
            local minW = parent._pveMinScrollWidth or parent:GetWidth() or 600
            local gridW = math.max(minW, bodyW + 2 * contentSideCached)
            local stackW = math.max(PvEStackBodyWidth(gridW, contentSideCached), bodyW)
            parent:SetWidth(gridW)
            parent._wnPveStackWidth = stackW
            if mf then mf._pveMinScrollWidth = gridW end
            if chr.SetWidth then
                chr:SetWidth(math.max(1, stackW))
            end
            local shells = _pveDrawPool.sectionShells
            if shells then
                for _, sh in pairs(shells) do
                    if sh and sh.header and sh.header.SetWidth then
                        sh.header:SetWidth(math.max(1, stackW))
                    end
                    if sh and sh.body and sh.body.SetWidth then
                        sh.body:SetWidth(math.max(1, stackW))
                    end
                end
            end
            if ns.PvEUI_ApplyLivePveSectionLayout then
                ns.PvEUI_ApplyLivePveSectionLayout(nil, parent)
            end
            local coreH = parent._pvePaintedCoreH or parent._pveLastBodyEstimate
                or PveEstimateScrollBodyHeight(rosterCount, 4)
            if mf and ns.UI_SyncMainTabScrollChrome then
                ns.UI_SyncMainTabScrollChrome(mf, parent, coreH)
            end
            if L.ns.PvE_ColumnPickerTryRefreshAfterDraw then
                L.ns.PvE_ColumnPickerTryRefreshAfterDraw(self)
            end
            return coreH
        end

        if parent._pveDrawSig ~= drawSig then
            if ns.PvEUI and ns.PvEUI.AbortChunkedPaint then
                ns.PvEUI.AbortChunkedPaint()
            end
            PveTeardownKeptBodyArtifacts(parent)
        end
        parent._pvePaintedCoreH = nil

        local estH = PveEstimateScrollBodyHeight(rosterCount, 4)
        parent._pveLastBodyEstimate = estH
        parent._pveDrawSig = drawSig

        local PvEUIState = ns.PvEUI
        PvEUIState._bodyPaintGen = (PvEUIState._bodyPaintGen or 0) + 1
        PvEUIState._bodyPaintCtx = {
            bodyOnly = true,
            drawSig = drawSig,
            scrollTopY = scrollTopY,
            columnDefs = PveCopyColumnDefs(PVE_COLUMNS),
            addon = self,
            parent = parent,
        }
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                ns.PvEUI.RunDeferredBodyPaint()
            end)
        else
            ns.PvEUI.RunDeferredBodyPaint()
        end
        return estH
    end

    local yOffset = scrollTopY

    -- Check if module is disabled - show beautiful disabled state card (before column strip / scroll width)
    if not L.ns.Utilities:IsModuleEnabled("pve") then
        L.WarbandNexus._pveVaultTooltipCharsSnapshot = {}
        local CreateDisabledCard = L.ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, GetLocalizedText("PVE_TITLE", "PvE Progress"))
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
    local currentPlayerKey = (L.ns.UI_GetSubsidiaryCharKey and L.ns.UI_GetSubsidiaryCharKey())
        or (L.ns.CharacterService and L.ns.CharacterService.ResolveSubsidiaryCharacterKey and L.ns.CharacterService:ResolveSubsidiaryCharacterKey(L.WarbandNexus, nil))
    
    -- Load sorting preferences from profile (persistent across sessions)
    if not parent.sortPrefsLoaded then
        parent.sortKey = (L.ns.CharacterService and L.ns.CharacterService.GetTabSortKey)
            and L.ns.CharacterService:GetTabSortKey(self.db.profile, "pve") or "default"
        parent.sortAscending = self.db.profile.pveSort and self.db.profile.pveSort.ascending
        parent.sortPrefsLoaded = true
    end
    
    if not self.db.profile.pveSort then self.db.profile.pveSort = {} end
    if profile then
        if not profile.pveSectionFilter then profile.pveSectionFilter = { sectionKey = "all" } end
        if L.ns.CharacterService and L.ns.CharacterService.EnsureCustomCharacterSectionsProfile then
            L.ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
        end
    end

    local rosterSortKey = (L.ns.CharacterService and L.ns.CharacterService.GetTabSortKey)
        and L.ns.CharacterService:GetTabSortKey(profile, "pve") or "default"
    local peelCurrentChar = (rosterSortKey == "default")

    -- Use the same sorting logic as Characters tab
    local currentChar = nil
    local favorites = {}
    local regular = {}
    
    for i = 1, #characters do
        local char = characters[i]
        -- Same canonical key as PvECacheService + row loop below (vault/M+ are per-key in pveCache)
        local charKey = GetRowCanonicalPvEKey(char)
        
        if peelCurrentChar and (charKey == currentPlayerKey
            or (L.ns.VaultCharKeysMatch and L.ns.VaultCharKeysMatch(charKey, currentPlayerKey))) then
            currentChar = char
        elseif L.ns.CharacterService and L.ns.CharacterService:IsFavoriteCharacter(self, charKey) then
            table.insert(favorites, char)
        else
            table.insert(regular, char)
        end
    end
    
    -- Sort function (with custom order support, same as Characters tab)
    local function sortCharacters(list, orderKey)
        local CS = L.ns.CharacterService
        if CS and CS.SortCharacterRosterList then
            return CS:SortCharacterRosterList(list, self.db.profile, orderKey, {
                tabId = "pve",
                compareNameFn = L.CompareCharNameLower,
                isLoggedInFn = function(char)
                    return CS:IsLoggedInCharacterRow(L.WarbandNexus, GetRowCanonicalPvEKey(char))
                end,
                getCharKeyFn = GetRowCanonicalPvEKey,
            })
        end
        table.sort(list, function(a, b)
            return L.CompareCharNameLower(a, b)
        end)
        return list
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
    local sortModeKey = rosterSortKey
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

    -- Merge: current first (default sort only), then favorites, then each custom group, then ungrouped regular
    local sortedCharacters = {}
    if peelCurrentChar and currentChar then
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

    if L.ns.PvELoadingState and L.ns.PvELoadingState.isLoading then
        local UI_CreateLoadingStateCard = L.ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local newYOffset = UI_CreateLoadingStateCard(
                parent,
                yOffset,
                L.ns.PvELoadingState,
                GetLocalizedText("LOADING_PVE", "Loading PvE Data...")
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
        local _, height = L.CreateEmptyStateCard(parent, "pve", yOffset)
        return yOffset + height
    end
    
    local tempMeasure = L.PvE_GetDrawPoolMeasureFS()
    tempMeasure:Hide()
    local maxNameRealmWidth = 0
    local measureNameW = ns.PvE_MeasureStackedNameColumnWidth
    if rosterChanged and measureNameW then
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
                local w = measureNameW(tempMeasure, nameStr, realmStr)
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
    local nameWidth = (ns.PvE_ResolveNameColumnWidth and ns.PvE_ResolveNameColumnWidth(maxNameRealmWidth))
        or math.max(100, math.ceil(maxNameRealmWidth) + 4)

    if #characters > 0 then
        local vbProfile = profile and profile.vaultButton or {}
        local layoutSig = L.PvE_BuildColumnLayoutSig(rosterSig, colSig, nameWidth, vbProfile)
        local layoutCache = L._pveDrawPool.columnLayout
        local layoutHit = layoutCache.sig == layoutSig and L.PvE_ApplyCachedColumnWidths(PVE_COLUMNS, layoutCache)
        if not layoutHit then
            PvE_ApplyAdaptiveColumnWidths(PVE_COLUMNS, {
                characters = characters,
                addon = self,
                getCharKey = GetRowCanonicalPvEKey,
                crests = PVE_DAWNCRESTS,
                shardsId = PVE_SHARDS_ID,
                keyId = PVE_RESTORED_KEY_ID,
                dundunId = L.PVE_DUNDUN_ID,
                voidcoreId = L.PVE_VOIDCORE_ID,
                manafluxId = L.PVE_MANAFLUX_ID,
                formatSeasonShift = ns.UI_FormatSeasonProgressShiftAware,
                compactShift = true,
                buildCompactHeader = function(col)
                    return PvE_BuildCompactHeaderLabel(col)
                end,
                formatVaultTrack = PvE_FormatVaultTrackColumn,
                formatNumber = FormatNumber,
                emDash = "\226\128\148",
                colIconSize = COL_ICON_SIZE,
            })
            L.PvE_SaveColumnLayoutCache(layoutCache, layoutSig, PVE_COLUMNS)
        end
    end

    -- Wide enough for left cluster + name + level/ilvl + inline columns → horizontal scrollbar when needed
    local inlineTotal = 0
    for pci = 1, #PVE_COLUMNS do
        inlineTotal = inlineTotal + PVE_COLUMNS[pci].width
    end
    for gi = 1, #PVE_COLUMNS - 1 do
        inlineTotal = inlineTotal + GapBetweenColumns(gi)
    end
    inlineTotal = inlineTotal + COL_RIGHT_MARGIN
    local gridInlineStartX = (L.PvE_ComputeInlineColumnsStartPx and L.PvE_ComputeInlineColumnsStartPx(nameWidth)) or 400
    local pveColumnDividerXs = (L.BuildPvEInlineColumnDividerXs and L.BuildPvEInlineColumnDividerXs(gridInlineStartX, PVE_COLUMNS, GapBetweenColumns)) or {}
    local minScrollW = 2 * contentSide + gridInlineStartX + inlineTotal
    local viewportPaintW = (stackWidth and stackWidth > 0) and (stackWidth + 2 * contentSide) or minScrollW
    local pveGridW = math.max(minScrollW, viewportPaintW)
    local pveStackW = math.max(PvEStackBodyWidth(pveGridW, contentSide), stackWidth or 0)
    parent:SetWidth(pveGridW)
    parent._wnPveStackWidth = pveStackW
    if mf then
        mf._pveMinScrollWidth = pveGridW
    end

    -- Crest/vault column headers live in scrollChild (scroll with the list). Not columnHeaderClip (Professions frozen strip).
    local mainFrameRef = mf or (L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame)
    local columnHeaderClip = mainFrameRef and mainFrameRef.columnHeaderClip
    if columnHeaderClip then
        columnHeaderClip:SetHeight(1)
        columnHeaderClip:Hide()
    end

    PvEParkAllColHeaderLabels()
    local colHeaderRow = L._pveDrawPool.colHeaderRow
    if colHeaderRow then
        colHeaderRow:SetParent(parent)
        colHeaderRow:Show()
    else
        colHeaderRow = L.ns.UI.Factory:CreateContainer(parent, pveStackW, COL_HEADER_HEIGHT)
        if not colHeaderRow then
            colHeaderRow = CreateFrame("Frame", nil, parent)
            colHeaderRow:SetSize(pveStackW, COL_HEADER_HEIGHT)
        end
        L._pveDrawPool.colHeaderRow = colHeaderRow
    end
    colHeaderRow._wnKeepOnTabSwitch = true
    colHeaderRow:SetHeight(COL_HEADER_HEIGHT)
    colHeaderRow:ClearAllPoints()
    colHeaderRow:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -yOffset)
    if colHeaderRow.SetWidth then
        colHeaderRow:SetWidth(math.max(1, pveStackW))
    end
    if colHeaderRow.bg then
        colHeaderRow.bg:Hide()
    end

    local function BuildCompactHeaderLabel(col)
        return PvE_BuildCompactHeaderLabel(col)
    end

    local colX = gridInlineStartX
    for hci = 1, #PVE_COLUMNS do
        local col = PVE_COLUMNS[hci]

        if col.icon or col.iconAtlas then
            local hitW, hitH = COL_ICON_SIZE + 4, COL_ICON_SIZE + 4
            local hitFrame = L._pveDrawPool.colHeaderHits[col.key]
            if hitFrame then
                hitFrame:SetParent(colHeaderRow)
                hitFrame:Show()
            else
                local PUFHdr = L.ns.UI and L.ns.UI.Factory
                hitFrame = PUFHdr and PUFHdr:CreateContainer(colHeaderRow, hitW, hitH, false)
                if not hitFrame then
                    hitFrame = CreateFrame("Frame", nil, colHeaderRow)
                    hitFrame:SetSize(hitW, hitH)
                end
                L._pveDrawPool.colHeaderHits[col.key] = hitFrame
            end
            hitFrame:SetSize(hitW, hitH)
            hitFrame:SetPoint("LEFT", colHeaderRow, "LEFT", colX + (col.width - hitW) * 0.5, 6)

            local iconTex = hitFrame._pveIconTex
            if not iconTex then
                iconTex = hitFrame:CreateTexture(nil, "ARTWORK")
                hitFrame._pveIconTex = iconTex
            end
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
            if ns.UI_EnsureTextureFullColor then
                ns.UI_EnsureTextureFullColor(iconTex)
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
                    })
                end)
                hitFrame:SetScript("OnLeave", function()
                    if L.HideTooltip then L.HideTooltip() end
                end)
                L.BindForwardScrollWheel(hitFrame)
            end
        end

        colX = colX + col.width
        if hci < #PVE_COLUMNS then
            colX = colX + GapBetweenColumns(hci)
        end
    end

    if L.UI_SyncGridColumnDividers and #pveColumnDividerXs > 0 then
        L.UI_SyncGridColumnDividers(colHeaderRow, pveColumnDividerXs, COL_HEADER_HEIGHT)
    end

    colHeaderRow:Show()
    yOffset = yOffset + COL_HEADER_HEIGHT + L.PVE_COLUMN_HEADER_PAD

    parent._pveSectionShellOrder = {}
    parent._pveColHeaderBottomY = yOffset
    parent._pveShellSectionGap = 4

    local totalLHBox = { v = yOffset }
    -- Same vertical rhythm as Characters virtual rows: `betweenRows` (often 0) after each 46px row.
    local PVE_CHAR_ROW_GAP = L.GetLayout().betweenRows or 0
    local scrollFrameRef = parent:GetParent()

    local function applyPveSectionReflow(rowHost, gap)
        ns.PvEUI_ApplyLivePveSectionLayout(rowHost, parent)
    end

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

    do
        local seenKeys = {}
        local deduped = {}
        for poi = 1, #paintOrder do
            local ent = paintOrder[poi]
            local ck = ent.char and GetRowCanonicalPvEKey(ent.char) or nil
            local dedupeKey = (ck or ("?" .. poi)) .. "\0" .. tostring(ent.secKey or "")
            if not seenKeys[dedupeKey] then
                seenKeys[dedupeKey] = true
                deduped[#deduped + 1] = ent
            end
        end
        paintOrder = deduped
    end

    local secBodies = {}
    local layoutTailForShell = nil

    local function finalizePveSectionContent(secKey)
        if not secKey or not profile then return end
        local body = secBodies[secKey]
        if not body then return end
        local h = body._pveRunningH or 0.1
        body._wnSectionFullH = h
        if not profile.ui then profile.ui = {} end
        local expanded = false
        if secKey == "pve_fav" then
            expanded = profile.ui.pveFavoritesExpanded == true
        elseif secKey == "pve_reg" then
            expanded = profile.ui.pveCharactersExpanded == true
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
            expanded = ev == true
        end
        if expanded then
            body:Show()
            PvEUI_ReflowSectionCharRows(body, PVE_CHAR_ROW_GAP)
            PvEUI_ReflowPveSectionShellChain(parent)
        else
            body:Hide()
            body:SetHeight(0.1)
        end
        body._pvePaintedSectionH = math.max(0.1, body._pveRunningH or body:GetHeight() or 0.1)
        layoutTailForShell = body
    end

    local prevDet = nil

    local PvEUIState = ns.PvEUI
    local function finalizePveCharPaint()
        if #paintOrder > 0 then
            finalizePveSectionContent(paintOrder[#paintOrder].secKey)
        end
    end

    local function paintPvERows(fromI, toI)
    for i = fromI, toI do
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

        -- All PvE character rows live under the collapsible section body (never directly under scrollChild).
        local rowHost
        if sk == "pve_fav" then
            if not secBodies[sk] then
                secBodies[sk] = L.PvEUI_CreatePvETabSectionShell(self, parent, profile, {
                    chars = favoritesDisplay,
                    headerLabel = GetLocalizedText("HEADER_FAVORITES", "Favorites"),
                    sectionUiKey = "pveFavoritesExpanded",
                    defaultExpanded = false,
                    headerAtlas = "GM-icon-assistActive-hover",
                    visualOpts = { sectionPreset = "gold" },
                    layoutTailFrame = layoutTailForShell,
                    totalLH = totalLHBox,
                    scrollFrameRef = scrollFrameRef,
                    yTop = totalLHBox.v,
                    sideMargin = contentSide,
                    stackWidth = pveStackW,
                })
            end
            rowHost = secBodies[sk]
        elseif sk == "pve_reg" then
            if not secBodies[sk] then
                secBodies[sk] = L.PvEUI_CreatePvETabSectionShell(self, parent, profile, {
                    chars = regularDisplay,
                    headerLabel = GetLocalizedText("HEADER_CHARACTERS", "Characters"),
                    sectionUiKey = "pveCharactersExpanded",
                    defaultExpanded = false,
                    headerAtlas = "GM-icon-headCount",
                    visualOpts = nil,
                    layoutTailFrame = layoutTailForShell,
                    totalLH = totalLHBox,
                    scrollFrameRef = scrollFrameRef,
                    yTop = totalLHBox.v,
                    sideMargin = contentSide,
                    stackWidth = pveStackW,
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
                    defaultExpanded = false,
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
                    sideMargin = contentSide,
                    stackWidth = pveStackW,
                })
            end
            rowHost = secBodies[sk]
        end
        assert(rowHost, "PvE row missing section body (sk=" .. tostring(sk) .. ")")

        local char = ent.char
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        -- Match DB keys (currency + PvE cache) — prefer characters table index via _key for canonical resolution.
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
            or (L.ns.VaultCharKeysMatch and L.ns.VaultCharKeysMatch(charKey, currentPlayerKey))
        local hasVaultReward = pve.hasUnclaimedRewards or false
        
        local charExpanded = L.IsExpanded(charExpandKey, false)

        local charDetailContent
        local buildPvEDetailIfNeeded

        local accVisual = L.BuildCollapsibleSectionOpts({
                bodyGetter = function() return charDetailContent end,
                -- Runs before SharedWidgets reads _wnSectionFullH for expand target height.
                persistFn = function(exp)
                    L.expandedStates[charExpandKey] = exp
                    if exp then
                        local detail = charDetailContent
                        local buildFn = detail and detail._pveBuildDetailFn
                        if buildFn then
                            buildFn()
                        elseif buildPvEDetailIfNeeded then
                            buildPvEDetailIfNeeded()
                        end
                    elseif charDetailContent then
                        charDetailContent:Hide()
                        charDetailContent:SetHeight(0.1)
                        charDetailContent._pvePaintedDetailH = 0.1
                    end
                    local host = rowHost
                    local sc = parent
                    if host and sc and C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            ns.PvEUI_ApplyLivePveSectionLayout(host, sc)
                        end)
                    elseif host and sc then
                        ns.PvEUI_ApplyLivePveSectionLayout(host, sc)
                    end
                end,
                refreshFn = function(exp)
                    if not exp then return end
                    local detail = charDetailContent
                    local buildFn = detail and detail._pveBuildDetailFn
                    if buildFn then
                        buildFn()
                    end
                    if detail and (not detail._wnSectionFullH or detail._wnSectionFullH < 2) and buildFn then
                        C_Timer.After(0, function()
                            if detail._pveBuildDetailFn then
                                detail._pveBuildDetailFn()
                            end
                            if detail._pveOnLayoutChanged and detail._wnSectionFullH then
                                local lh = math.max(0.1, detail._wnSectionFullH)
                                detail:SetHeight(lh)
                                detail:Show()
                                detail._pveOnLayoutChanged(lh)
                            end
                        end)
                    end
                end,
                -- Live expand/collapse: re-chain rows + section shells (Storage-tab pattern).
                onUpdate = function(drawH)
                    local dh = math.max(0.1, tonumber(drawH) or 0.1)
                    local collapsing = dh < 2
                    if charDetailContent then
                        charDetailContent:SetHeight(collapsing and 0.1 or dh)
                        if collapsing then
                            charDetailContent:Hide()
                            charDetailContent._pvePaintedDetailH = 0.1
                        else
                            charDetailContent._wnSectionFullH = dh
                            charDetailContent:Show()
                        end
                    end
                    applyPveSectionReflow(rowHost, interRowGap)
                end,
                onComplete = function(exp)
                    if charDetailContent then
                        if exp then
                            charDetailContent._pvePaintedDetailH = PvEUI_ResolveCharDetailPaintHeight(charDetailContent)
                        else
                            charDetailContent:Hide()
                            charDetailContent:SetHeight(0.1)
                            charDetailContent._pvePaintedDetailH = 0.1
                        end
                    end
                    applyPveSectionReflow(rowHost, interRowGap)
                end,
            }) or {}
        accVisual.suppressSectionChrome = true
        accVisual.sectionHeaderHeight = 46
        -- Populate detail before reading _wnSectionFullH (persistFn); defer left false so onToggle re-reads height after build.
        accVisual.deferOnToggleUntilComplete = false

        local charHeader, charDetailContent, expandIconTex, rowReused = L.PvEAcquireCharRowFrames(rowHost, charKey)
        if not rowReused then
            charHeader, expandIconTex = L.CreateCollapsibleHeader(
                rowHost,
                "",
                charExpandKey,
                charExpanded,
                function(isExpanded)
                    if isExpanded then
                        if charDetailContent then
                            charDetailContent:Show()
                            charDetailContent:SetHeight(math.max(0.1, charDetailContent._wnSectionFullH or 0.1))
                        end
                    elseif charDetailContent then
                        charDetailContent:Hide()
                        charDetailContent:SetHeight(0.1)
                    end
                end,
                nil, nil, nil, true,
                accVisual
            )
            charDetailContent = L.ns.UI.Factory:CreateContainer(rowHost)
            charDetailContent:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, 0)
            charDetailContent:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)
            if charDetailContent.SetClipsChildren then
                charDetailContent:SetClipsChildren(true)
            end
            L._pveDrawPool.charRows[charKey] = {
                header = charHeader,
                detail = charDetailContent,
                expandIcon = expandIconTex,
            }
        end
        if charHeader then
            charHeader._wnCollVisualOpts = accVisual
        end
        if rowReused and charHeader and charDetailContent then
            charDetailContent:ClearAllPoints()
            charDetailContent:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, 0)
            charDetailContent:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)
            if charDetailContent.SetClipsChildren then
                charDetailContent:SetClipsChildren(true)
            end
        end
        if prevDet == nil then
            rowHost._pveCharKeysOrdered = {}
            rowHost._pveRunningH = 0
            charHeader:SetPoint("TOPLEFT", rowHost, "TOPLEFT", 0, 0)
            charHeader:SetPoint("TOPRIGHT", rowHost, "TOPRIGHT", 0, 0)
        else
            charHeader:SetPoint("TOPLEFT", prevDet, "BOTTOMLEFT", 0, -interRowGap)
            charHeader:SetPoint("TOPRIGHT", prevDet, "BOTTOMRIGHT", 0, -interRowGap)
        end
        rowHost._pveCharKeysOrdered = rowHost._pveCharKeysOrdered or {}
        rowHost._pveCharKeysOrdered[#rowHost._pveCharKeysOrdered + 1] = charKey
        rowHost._pveScrollChild = parent
        rowHost._pveScrollFrameRef = scrollFrameRef
        rowHost._pveRowGap = interRowGap
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

            -- Claimable loot: GetVaultStatusForChar (live API for current char; cache + reset for alts).
            local vaultLootClaimable = false
            local vsCached = L.PvE_GetVaultStatusCached and L.PvE_GetVaultStatusCached(L.WarbandNexus, charKey)
            if vsCached then
                vaultLootClaimable = vsCached.isReady == true
            else
                vaultLootClaimable = ns.CharHasClaimableVaultReward
                    and ns.CharHasClaimableVaultReward(charKey) == true
            end

            local profileVault = L.WarbandNexus and L.WarbandNexus.db and L.WarbandNexus.db.profile
            local vbCols = profileVault and profileVault.vaultButton or {}
            local function BuildVaultColumnBind(activityList, slotCount, typeName)
                if L.ns.VaultSlotsFromActivityList and L.ns.VaultFormatCategoryColumn then
                    local slots, catKey = L.ns.VaultSlotsFromActivityList(activityList, slotCount, typeName)
                    return {
                        slots = slots,
                        category = catKey,
                        showRewardProgress = vbCols.showRewardProgress == true,
                        showRewardItemLevel = vbCols.showRewardItemLevel == true,
                        vaultLootClaimable = vaultLootClaimable == true,
                        pveDisplayMode = true,
                    }
                end
                return nil
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
                local currentLabel = GetLocalizedText("CURRENT_ENTRIES_LABEL", "Current:")
                local seasonLabel = GetLocalizedText("SEASON", "Season")
                local weeklyLabel = GetLocalizedText("CURRENCY_LABEL_WEEKLY", "Weekly")
                local remainingSuffix = GetLocalizedText("VAULT_REMAINING_SUFFIX", "remaining")
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

                if L.ns.Utilities and L.ns.Utilities.IsWeeklyCapCurrency and L.ns.Utilities:IsWeeklyCapCurrency(currencyID, currencyName) then
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
                            text = GetLocalizedText("CREST_SOURCES_HEADER", "Sources:"),
                            color = {1, 0.82, 0},
                        })
                        for si = 1, #sources do
                            table.insert(lines, { text = "\194\183 " .. sources[si], color = {0.82, 0.86, 0.95} })
                        end
                        if remSeason > 0 then
                            table.insert(lines, {
                                text = string.format("%s %s",
                                    L.FormatNumber(remSeason),
                                    GetLocalizedText("CREST_TO_CAP_SUFFIX", "to season cap")),
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

            -- Shared grid X: header + every row (see PvE_ComputeInlineColumnsStartPx / row chrome).
            local inlineX = gridInlineStartX
            local colValuesByKey = {}

            local mutedC = COLORS.textMuted or { 0.53, 0.53, 0.53, 1 }
            local brightC = COLORS.textBright or { 1, 1, 1, 1 }
            local dimHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cff888888"
            local DIM_COLOR = { mutedC[1], mutedC[2], mutedC[3] }
            local NORMAL_COLOR = { brightC[1], brightC[2], brightC[3] }
            local CAP_OPEN_COLOR = {0.5, 1, 0.5}
            local CAPPED_COLOR = {1, 0.35, 0.35}
            local EM_DASH = "\226\128\148"
            local EM_DASH_RICH = dimHex .. EM_DASH .. "|r"

            local function GetCapStateColor(currencyID, currencyName, qty, maxQty, totalEarned, seasonMax)
                if L.ns.Utilities and L.ns.Utilities.IsCofferKeyShardCurrency and L.ns.Utilities:IsCofferKeyShardCurrency(currencyID, currencyName) then
                    local cap = tonumber(maxQty) or 0
                    local teN = tonumber(totalEarned)
                    if cap > 0 and teN ~= nil then
                        return (teN >= cap) and CAPPED_COLOR or CAP_OPEN_COLOR
                    end
                    return NORMAL_COLOR
                end
                if L.ns.Utilities and L.ns.Utilities.IsWeeklyCapCurrency and L.ns.Utilities:IsWeeklyCapCurrency(currencyID, currencyName) then
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
                local tipTitle = PVE_DAWNCRESTS[i] and PVE_DAWNCRESTS[i].name or (GetLocalizedText("TAB_CURRENCY", "Currency"))
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
                tooltipTitle = GetLocalizedText("PVE_COL_COFFER_SHARDS", "Coffer Shards"),
                tooltipIcon = shardData and shardData.icon,
                currencyID = PVE_SHARDS_ID,
                seasonProgressData = shardData,
            }
            local keyMax = keyData and keyData.maxQuantity or 0
            local keyTE = keyData and keyData.totalEarned
            local keySM = keyData and keyData.seasonMax
            local keyTxt = FormatSeasonLine and FormatSeasonLine(keyData) or FormatCurrencyStatus(keyQty)
            colValuesByKey.restored_key = {
                text = keyTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((keyTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(PVE_RESTORED_KEY_ID, keyData and keyData.name, keyQty, keyMax, keyTE, keySM)) or nil,
                tooltip = BuildCurrencyTooltip(PVE_RESTORED_KEY_ID, keyData and keyData.name, keyQty, keyMax, keyTE, keySM),
                tooltipTitle = GetLocalizedText("PVE_COL_RESTORED_KEY", "Restored Coffer Key"),
                tooltipIcon = keyData and keyData.icon,
                currencyID = PVE_RESTORED_KEY_ID,
                seasonProgressData = keyData,
            }
            local dundunData = L.WarbandNexus:GetCurrencyData(L.PVE_DUNDUN_ID, charKey)
            local dqty = (dundunData and tonumber(dundunData.quantity)) or 0
            local dmax = (dundunData and dundunData.maxQuantity) or 0
            local dte = dundunData and dundunData.totalEarned
            local dsm = dundunData and dundunData.seasonMax
            local dundunTxt = FormatSeasonLine and FormatSeasonLine(dundunData) or FormatCurrencyStatus(dqty)
            colValuesByKey.shard_of_dundun = {
                text = dundunTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((dundunTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(L.PVE_DUNDUN_ID, dundunData and dundunData.name, dqty, dmax, dte, dsm)) or nil,
                tooltip = BuildCurrencyTooltip(L.PVE_DUNDUN_ID, dundunData and dundunData.name, dqty, dmax, dte, dsm),
                tooltipTitle = L.GetLocalizedText("PVE_COL_SHARD_OF_DUNDUN", "Shard of Dundun"),
                tooltipIcon = dundunData and dundunData.icon,
                currencyID = L.PVE_DUNDUN_ID,
                seasonProgressData = dundunData,
            }
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
                local catTitle = (category == "Raid") and (GetLocalizedText("PVE_HEADER_RAIDS", "Raids"))
                    or (category == "M+") and (GetLocalizedText("PVE_HEADER_DUNGEONS", "Dungeons"))
                    or (GetLocalizedText("VAULT_WORLD", "World"))
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
                                .. L.GetLocalizedText("ILVL_FORMAT", "iLvl %d"):format(rewardIlvl)
                        end
                        table.insert(lines, {
                            text = L.GetLocalizedText("PVE_VAULT_SLOT_COMPLETE_FORMAT", "Slot %d: |cff80ff80\226\156\147|r %s"):format(i, rhs ~= "" and rhs or L.GetLocalizedText("PVE_VAULT_SLOT_UNLOCKED", "Unlocked")),
                            color = {0.85, 0.9, 0.95},
                        })
                    elseif thresh > 0 then
                        local shiftHeld = IsShiftKeyDown and IsShiftKeyDown()
                        local rem = thresh - prog
                        local progressLine
                        if shiftHeld and rem > 0 then
                            progressLine = L.GetLocalizedText("PVE_VAULT_SLOT_REMAINING_FORMAT", "Slot %d: |cffffcc00%d|r more"):format(i, rem)
                        else
                            progressLine = L.GetLocalizedText("PVE_VAULT_SLOT_PROGRESS_FORMAT", "Slot %d: |cffff8888%d/%d|r"):format(i, prog, thresh)
                        end
                        table.insert(lines, {
                            text = progressLine,
                            color = {0.65, 0.65, 0.65},
                        })
                    else
                        table.insert(lines, { text = L.GetLocalizedText("PVE_VAULT_SLOT_EMPTY_FORMAT", "Slot %d: \226\128\148"):format(i), color = DIM_COLOR })
                    end
                end
                return lines
            end

            colValuesByKey.slot1 = {
                text = FormatVaultTrackSlots(vaultActs.raids, raidTotal, "Raid"),
                vaultColumnData = BuildVaultColumnBind(vaultActs.raids, raidTotal, "Raid"),
                color = {1, 1, 1},
                tooltip = BuildVaultSlotTooltipLines(vaultActs.raids, "Raid", raidTotal),
                tooltipTitle = GetLocalizedText("PVE_HEADER_RAIDS", "Raids"),
            }
            colValuesByKey.slot2 = {
                text = FormatVaultTrackSlots(vaultActs.mythicPlus, dungeonTotal, "M+"),
                vaultColumnData = BuildVaultColumnBind(vaultActs.mythicPlus, dungeonTotal, "M+"),
                color = {1, 1, 1},
                tooltip = BuildVaultSlotTooltipLines(vaultActs.mythicPlus, "M+", dungeonTotal),
                tooltipTitle = GetLocalizedText("PVE_HEADER_DUNGEONS", "Dungeons"),
            }
            colValuesByKey.slot3 = {
                text = FormatVaultTrackSlots(vaultActs.world, worldTotal, "World"),
                vaultColumnData = BuildVaultColumnBind(vaultActs.world, worldTotal, "World"),
                color = {1, 1, 1},
                tooltip = BuildVaultSlotTooltipLines(vaultActs.world, "World", worldTotal),
                tooltipTitle = GetLocalizedText("VAULT_WORLD", "World"),
            }
            -- Trovehunter's Bounty / bountiful weeklies: per-character snapshot from PvE cache (not live API on every row).
            local delveChar = (pve.delves and pve.delves.character) or {}
            local bountifulDone = delveChar.bountifulComplete
            if bountifulDone == nil and isCurrentChar then
                bountifulDone = L.WarbandNexus.IsBountifulDelveWeeklyDone and L.WarbandNexus:IsBountifulDelveWeeklyDone() or false
            end
            local bountifulTitle = GetLocalizedText("BOUNTIFUL_DELVE", "Trovehunter's Bounty")
            local bountifulUnknown = (bountifulDone == nil)
            local bountifulTip = {
                {
                    text = bountifulUnknown and (GetLocalizedText("PVE_BOUNTY_NEED_LOGIN", "No saved status for this character. Log in to refresh."))
                        or (bountifulDone and (GetLocalizedText("VAULT_COMPLETED_ACTIVITIES", "Completed"))
                            or (GetLocalizedText("ACHIEVEMENT_NOT_COMPLETED", "Not Completed"))),
                    color = {1, 1, 1},
                },
            }
            colValuesByKey.bountiful = {
                text = bountifulUnknown and EM_DASH or (bountifulDone and L.VAULT_SLOT_CHECK or L.VAULT_SLOT_CROSS),
                color = bountifulUnknown and DIM_COLOR or {1, 1, 1},
                tooltip = bountifulTip,
                tooltipTitle = bountifulTitle,
                tooltipIcon = L.GetTrovehunterBountyColumnIcon(),
                pveBountyData = {
                    done = bountifulDone == true,
                    unknown = bountifulUnknown,
                },
            }
            local voidcoreData = L.WarbandNexus:GetCurrencyData(L.PVE_VOIDCORE_ID, charKey)
            local vqty = (voidcoreData and tonumber(voidcoreData.quantity)) or 0
            local vmax = (voidcoreData and voidcoreData.maxQuantity) or 0
            local vte = voidcoreData and voidcoreData.totalEarned
            local vsm = voidcoreData and voidcoreData.seasonMax
            local voidcoreTxt = FormatSeasonLine and FormatSeasonLine(voidcoreData) or FormatCurrencyStatus(vqty)
            colValuesByKey.voidcore = {
                text = voidcoreTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((voidcoreTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(L.PVE_VOIDCORE_ID, voidcoreData and voidcoreData.name, vqty, vmax, vte, vsm)) or nil,
                tooltip = BuildCurrencyTooltip(L.PVE_VOIDCORE_ID, voidcoreData and voidcoreData.name, vqty, vmax, vte, vsm),
                tooltipTitle = L.GetLocalizedText("PVE_COL_NEBULOUS_VOIDCORE", "Nebulous Voidcore"),
                tooltipIcon = voidcoreData and voidcoreData.icon,
                currencyID = L.PVE_VOIDCORE_ID,
                seasonProgressData = voidcoreData,
            }
            -- Vault Status (matches Vault Tracker quick window readout):
            --   Ready -> "Ready to Claim" (green)
            --   ReadySlots > 0 -> "<n> Slots Earned" (cyan)
            --   Pending only -> "Pending..." (gold)
            --   No progress -> em-dash dimmed
            do
                local vs = L.PvE_GetVaultStatusCached and L.PvE_GetVaultStatusCached(L.WarbandNexus, charKey)
                local statusTxt
                if not vs then
                    statusTxt = EM_DASH_RICH
                elseif vs.isReady then
                    statusTxt = "|cff44ff44" .. (GetLocalizedText("VAULT_READY_TO_CLAIM", "Ready to Claim")) .. "|r"
                elseif vs.claimedThisWeek and not vs.isReady then
                    statusTxt = "|cffffd700" .. (GetLocalizedText("VAULT_PENDING", "Pending\226\128\166")) .. "|r"
                elseif (vs.readySlots or 0) > 0 then
                    statusTxt = "|cff66ddff" .. L.GetLocalizedText("VAULT_SLOTS_SHORT_FORMAT", "%d Slots"):format(tonumber(vs.readySlots) or 0) .. "|r"
                else
                    statusTxt = "|cffffd700" .. (GetLocalizedText("VAULT_PENDING", "Pending\226\128\166")) .. "|r"
                end
                colValuesByKey.vault_status = {
                    text = statusTxt,
                    richText = true,
                }
            end

            local manafluxData = L.WarbandNexus:GetCurrencyData(L.PVE_MANAFLUX_ID, charKey)
            local manafluxQty = (manafluxData and manafluxData.quantity) or 0
            local mfMax = (manafluxData and manafluxData.maxQuantity) or 0
            local mfTe = manafluxData and manafluxData.totalEarned
            local mfSm = manafluxData and manafluxData.seasonMax
            local mfTxt = FormatSeasonLine and FormatSeasonLine(manafluxData) or FormatCurrencyStatus(manafluxQty)
            colValuesByKey.manaflux = {
                text = mfTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((mfTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(L.PVE_MANAFLUX_ID, manafluxData and manafluxData.name, manafluxQty, mfMax, mfTe, mfSm)) or nil,
                tooltip = BuildCurrencyTooltip(L.PVE_MANAFLUX_ID, manafluxData and manafluxData.name, manafluxQty, mfMax, mfTe, mfSm),
                tooltipTitle = L.GetLocalizedText("PVE_COL_DAWNLIGHT_MANAFLUX", "Dawnlight Manaflux"),
                tooltipIcon = manafluxData and manafluxData.icon,
                currencyID = L.PVE_MANAFLUX_ID,
                seasonProgressData = manafluxData,
            }

            local UnbindSeason = L.ns.UI_UnbindSeasonProgressAmount
            local UnbindVaultCol = L.ns.UI_UnbindVaultColumnDisplay
            local UnbindBounty = L.ns.UI_UnbindPvEBountyDisplay
            for ci = 1, #PVE_COLUMNS do
                local col = PVE_COLUMNS[ci]
                local val = colValuesByKey[col.key]
                if val then
                    local cw = col.width
                    local colCenterX = inlineX + cw * 0.5
                    local cell = L.PvEAcquireInlineCell(charHeader, charKey, col.key)
                    local colText = cell.fs
                    colText:SetPoint("CENTER", charHeader, "LEFT", colCenterX, 0)
                    colText:SetWidth(cw)
                    colText:SetJustifyH("CENTER")
                    if colText.SetJustifyV then colText:SetJustifyV("MIDDLE") end
                    colText:SetWordWrap(false)
                    if val.vaultColumnData and L.ns.UI_BindVaultColumnDisplay then
                        if UnbindSeason then UnbindSeason(colText) end
                        if UnbindBounty then UnbindBounty(colText) end
                        L.ns.UI_BindVaultColumnDisplay(colText, val.vaultColumnData)
                        ns.UI_SetTextColorRole(colText, "Bright")
                    elseif val.seasonProgressData and L.ns.UI_BindSeasonProgressAmount then
                        if UnbindVaultCol then UnbindVaultCol(colText) end
                        if UnbindBounty then UnbindBounty(colText) end
                        L.ns.UI_BindSeasonProgressAmount(colText, val.seasonProgressData, {
                            compactShift = true,
                            pveDisplayMode = true,
                        })
                        ns.UI_SetTextColorRole(colText, "Bright")
                    elseif val.pveBountyData and L.ns.UI_BindPvEBountyDisplay then
                        if UnbindSeason then UnbindSeason(colText) end
                        if UnbindVaultCol then UnbindVaultCol(colText) end
                        L.ns.UI_BindPvEBountyDisplay(colText, val.pveBountyData)
                        ns.UI_SetTextColorRole(colText, "Bright")
                    else
                        if UnbindSeason then UnbindSeason(colText) end
                        if UnbindVaultCol then UnbindVaultCol(colText) end
                        if UnbindBounty then UnbindBounty(colText) end
                        colText:SetText(val.text)
                        if not val.richText and val.color then
                            colText:SetTextColor(val.color[1], val.color[2], val.color[3])
                        elseif val.richText then
                            ns.UI_SetTextColorRole(colText, "Bright")
                        end
                    end
                    if val.tooltip and L.ShowTooltip then
                        local hit = cell.hit
                        if not hit then
                            local PUF = L.ns.UI and L.ns.UI.Factory
                            local cw0, ch0 = cw, math.max(L.ROW_HEIGHT or 26, charHeader:GetHeight() or 46)
                            hit = PUF and PUF:CreateContainer(charHeader, cw0, ch0, false)
                            if not hit then
                                hit = CreateFrame("Frame", nil, charHeader)
                            end
                            cell.hit = hit
                            hit:EnableMouse(true)
                            L.BindForwardScrollWheel(hit)
                        end
                        hit:SetParent(charHeader)
                        hit:SetPoint("CENTER", charHeader, "LEFT", colCenterX, 0)
                        hit:SetSize(cw, math.max(L.ROW_HEIGHT or 26, charHeader:GetHeight() or 46))
                        hit:Show()
                        hit:SetScript("OnEnter", function(self)
                            if val.currencyID then
                                L.ShowTooltip(self, {
                                    type = "currency",
                                    currencyID = val.currencyID,
                                    charKey = charKey,
                                })
                            else
                                L.ShowTooltip(self, {
                                    type = "custom",
                                    icon = val.tooltipIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                    title = val.tooltipTitle or (GetLocalizedText("TAB_CURRENCY", "Currency")),
                                    lines = val.tooltip,
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
                    inlineX = inlineX + cw
                    if ci < #PVE_COLUMNS then
                        inlineX = inlineX + GapBetweenColumns(ci)
                    end
                end
            end
            if L.UI_SyncGridColumnDividers and #pveColumnDividerXs > 0 then
                L.UI_SyncGridColumnDividers(charHeader, pveColumnDividerXs, charHeader:GetHeight() or PVE_CHAR_ROW_HEADER_H)
            end
        end
        
        charHeader:SetAlpha(1)

        -- BuildCollapsibleSectionOpts exposes config.onUpdate as sectionOnUpdate (not .onUpdate).
        charDetailContent._pveOnLayoutChanged = accVisual.sectionOnUpdate
        charDetailContent._pveLayoutHost = rowHost

        buildPvEDetailIfNeeded = function()
            ns.PvEUI_PopulateExpandedCharacterDetail(self, parent, charDetailContent, charExpandKey, charKey, pve, pveData, isCurrentChar)
        end
        if charDetailContent then
            charDetailContent._pveBuildDetailFn = buildPvEDetailIfNeeded
        end

        if charExpanded then
            buildPvEDetailIfNeeded()
            local dh = charDetailContent._wnSectionFullH or 200
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
                inc = PVE_CHAR_ROW_HEADER_H + (charDetailContent._wnSectionFullH or 200) + interRowGap
            else
                inc = PVE_CHAR_ROW_HEADER_H + 0.1 + interRowGap
            end
            bod._pveRunningH = (bod._pveRunningH or 0) + inc
            bod._pvePaintedSectionH = bod._pveRunningH
        end

        prevDet = charDetailContent

    -- Character sections flow directly one after another (like Characters tab)
    end
    end

    local chunkPaintScheduled = false
    local estimatedBodyH = totalLHBox.v + 12
    if #paintOrder > 0 then
        estimatedBodyH = estimatedBodyH + #paintOrder * (PVE_CHAR_ROW_HEADER_H + PVE_CHAR_ROW_GAP) + 80
        local pvePaintDrawGen = PvEUIState._paintDrawGen or 0
        local pveChunkSize = PvEUIState.PAINT_CHUNK_SIZE or 2
        local pvePaintCursor = 1

        if #paintOrder <= 1 then
            paintPvERows(1, #paintOrder)
            finalizePveCharPaint()
            estimatedBodyH = totalLHBox.v + 12
        else
            chunkPaintScheduled = true
            parent._pveChunkPaintPending = true
            local function pumpPvePaint()
                if PvEUIState._paintDrawGen ~= pvePaintDrawGen then
                    parent._pveChunkPaintPending = nil
                    return
                end
                if not mf or not mf:IsShown() or mf.currentTab ~= "pve" then
                    parent._pveChunkPaintPending = nil
                    return
                end
                local toI = math.min(pvePaintCursor + pveChunkSize - 1, #paintOrder)
                paintPvERows(pvePaintCursor, toI)
                pvePaintCursor = toI + 1
                if pvePaintCursor > #paintOrder then
                    finalizePveCharPaint()
                    if ns.PvEUI_ApplyLivePveSectionLayout then
                        ns.PvEUI_ApplyLivePveSectionLayout(nil, parent)
                    end
                    local coreHDone = parent._pvePaintedCoreH or (totalLHBox.v + 12)
                    parent._pvePaintedCoreH = coreHDone
                    parent._pveChunkPaintPending = nil
                    if mf and ns.UI_SyncMainTabScrollChrome then
                        ns.UI_SyncMainTabScrollChrome(mf, parent, coreHDone)
                    end
                    return
                end
                if mf and ns.UI_SyncMainTabScrollChrome then
                    ns.UI_SyncMainTabScrollChrome(mf, parent, totalLHBox.v + 12)
                end
                C_Timer.After(0, pumpPvePaint)
            end
            C_Timer.After(0, pumpPvePaint)
        end
    end

    local coreH = chunkPaintScheduled and estimatedBodyH or (totalLHBox.v + 12)
    if not chunkPaintScheduled and ns.PvEUI_ApplyLivePveSectionLayout then
        ns.PvEUI_ApplyLivePveSectionLayout(nil, parent)
        coreH = parent._pvePaintedCoreH or coreH
    end
    parent._pvePaintedCoreH = coreH
    parent._pveBodyReady = true
    parent._pveDrawSig = drawSig
    parent._pveLastBodyEstimate = coreH
    if not chunkPaintScheduled and mf and ns.UI_SyncMainTabScrollChrome then
        ns.UI_SyncMainTabScrollChrome(mf, parent, coreH)
    end
    if L.ns.PvE_ColumnPickerTryRefreshAfterDraw then
        L.ns.PvE_ColumnPickerTryRefreshAfterDraw(self)
    end
    return coreH
end

function ns.PvEUI.RunDeferredBodyPaint()
    local PvEUIState = ns.PvEUI
    local ctx = PvEUIState._bodyPaintCtx
    if not ctx then return end
    PvEUIState._bodyPaintCtx = nil
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "pve" then return end
    if InCombatLockdown and InCombatLockdown() then
        PvEUIState._bodyPaintCtx = ctx
        if C_Timer and C_Timer.After then
            C_Timer.After(0, ns.PvEUI.RunDeferredBodyPaint)
        end
        return
    end
    PvEUI_DrawPvEProgressBody(ctx.addon, ctx.parent, ns.PvEDrawLibs, ctx)
end

--- Header chest icon: all tracked characters' vault column summaries (Raid / M+ / World), width-aware row cap.

function WarbandNexus:DrawPvEProgress(parent)
    return PvEUI_DrawPvEProgressBody(self, parent, ns.PvEDrawLibs)
end

function WarbandNexus:ShowPvEVaultAllCharactersTooltip(anchorFrame)
    if not anchorFrame or not ShowTooltip then return end

    local snap = self._pveVaultTooltipCharsSnapshot
    local lines = {}

    local title = GetLocalizedText("VAULT_SUMMARY_ALL_TITLE", "Great Vault — all characters")
    table.insert(lines, {
        text = GetLocalizedText("VAULT_SUMMARY_ALL_SUB", "Raid · Mythic+ · World columns match the PvE tab."),
        color = { 0.72, 0.72, 0.76 },
    })
    table.insert(lines, { type = "spacer", height = 6 })

    local currentKey = (ns.UI_GetSubsidiaryCharKey and ns.UI_GetSubsidiaryCharKey())
        or (ns.CharacterService and ns.CharacterService.ResolveSubsidiaryCharacterKey and ns.CharacterService:ResolveSubsidiaryCharacterKey(WarbandNexus, nil))

    local sh = GetScreenHeight() or 1080
    local sw = GetScreenWidth() or 1920
    local maxRows = math.max(24, math.min(100, math.floor((sh * 0.52) / 15)))
    local maxW = math.floor(sw * 0.42)
    if maxW < 360 then maxW = 360 end
    if maxW > 620 then maxW = 620 end

    if not snap or #snap == 0 then
        table.insert(lines, {
            text = GetLocalizedText("VAULT_SUMMARY_NO_CHARS", "No tracked characters."),
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

                local claim = false
                if self.GetVaultStatusForChar then
                    local vs = self:GetVaultStatusForChar(charKey)
                    claim = vs and vs.isReady == true
                else
                    claim = pveData.vaultRewards and pveData.vaultRewards.hasAvailableRewards == true
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

        local hdrName = GetLocalizedText("VAULT_SUMMARY_COL_NAME", "Character")
        local hdrRealm = GetLocalizedText("VAULT_SUMMARY_COL_REALM", "Realm")
        local hdrRaid = GetLocalizedText("PVE_HEADER_RAIDS", "Raids")
        local hdrMPlus = GetLocalizedText("PVE_HEADER_DUNGEONS", "M+")
        local hdrWorld = GetLocalizedText("VAULT_WORLD", "World")

        local FontManager = ns.FontManager
        local measure = FontManager and FontManager:CreateFontString(UIParent, "body", "OVERLAY")
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
                text = string.format(GetLocalizedText("VAULT_SUMMARY_MORE", "… and %d more (see PvE list)."), notShown),
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
        maxWidth = maxW,
    })
end

if ns.UI_LayoutCoordinator then
    local LC = ns.UI_LayoutCoordinator
    local function PveTabViewportRelayout(scrollChild, contentWidth, mf)
        if not mf or mf.currentTab ~= "pve" then return false end
        if scrollChild and contentWidth and contentWidth > 0 then
            local contentSide = scrollChild._wnPveContentSide or SIDE_MARGIN
            local bodyW = math.max(200, contentWidth - contentSide * 2)
            local minW = scrollChild._pveMinScrollWidth or scrollChild:GetWidth() or 0
            local gridW = math.max(minW, contentWidth)
            local stackW = math.max(PvEStackBodyWidth(gridW, contentSide), bodyW)
            scrollChild:SetWidth(gridW)
            scrollChild._wnPveStackWidth = stackW
            mf._pveMinScrollWidth = gridW
            local chr = _pveDrawPool.colHeaderRow
            if chr and chr.SetWidth then
                chr:SetWidth(math.max(1, stackW))
            end
            local shells = _pveDrawPool.sectionShells
            if shells then
                for _, sh in pairs(shells) do
                    if sh and sh.header and sh.header.SetWidth then
                        sh.header:SetWidth(math.max(1, stackW))
                    end
                    if sh and sh.body and sh.body.SetWidth then
                        sh.body:SetWidth(math.max(1, stackW))
                    end
                end
            end
            local rows = _pveDrawPool.charRows
            if rows then
                for _, row in pairs(rows) do
                    if row and row.header and row.header.SetWidth then
                        row.header:SetWidth(math.max(1, stackW))
                    end
                end
            end
        end
        if ns.UI_RefreshFixedHeaderChrome then
            ns.UI_RefreshFixedHeaderChrome(mf)
        end
        if ns.UI_SyncMainScrollBarColumns then
            ns.UI_SyncMainScrollBarColumns(mf)
        end
        return false
    end
    LC:RegisterTabAdapter("pve", {
        OnViewportWidthChanged = function(scrollChild, contentWidth, mf)
            if not mf or mf.currentTab ~= "pve" then return false end
            -- Characters / Professions: no tab body work while corner grip is held.
            if ns.UI_IsMainFrameResizeSession and ns.UI_IsMainFrameResizeSession(mf) then
                return true
            end
            return PveTabViewportRelayout(scrollChild, contentWidth, mf)
        end,
        OnViewportLayoutCommit = function(scrollChild, contentWidth, mf)
            if not mf or mf.currentTab ~= "pve" then return false end
            PveTabViewportRelayout(scrollChild, contentWidth, mf)
            if WarbandNexus and WarbandNexus.PopulateContent then
                WarbandNexus:PopulateContent(true)
            end
            return true
        end,
    })
end
