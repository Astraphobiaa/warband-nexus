--[[
    Warband Nexus - Reputation Tab
    Display all reputations across characters with progress bars, Renown, and Paragon support

    WN_FACTORY: Row progress bar shells use `Factory:CreateContainer` when available (inline pooled bar has
    custom BORDER/ARTWORK textures; fall back to plain `CreateFrame` if Factory absent).

    Hierarchy (All Characters view - matches Filtered View):
    - Character Header (0px) â†’ HEADER_SPACING (40px)
      - Expansion Header (BASE_INDENT = 15px) â†’ HEADER_HEIGHT (32px)
        - Reputation Rows (BASE_INDENT = 15px, same as header)
        - Sub-Rows (BASE_INDENT + BASE_INDENT + SUBROW_EXTRA_INDENT = 40px)
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local E = Constants.EVENTS
local FontManager = ns.FontManager  -- Centralized font management
local ReputationUIEvents = {} -- Unique AceEvent identity for this module

local issecretvalue = issecretvalue

local function SafeLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

-- Debug helper
local DebugPrint = (ns.CreateDebugPrinter and ns.CreateDebugPrinter("|cff00ff00[RepUI]|r"))
    or ns.DebugPrint
    or function() end
local IsDebugModeEnabled = ns.IsDebugModeEnabled

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Import shared UI components
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateNoticeFrame = ns.UI_CreateNoticeFrame
local CreateIcon = ns.UI_CreateIcon
-- Progress bar is inline lazy-created on pooled rows (no shared widget import)
-- (eliminates ~150 Frame + ~900 texture creations per refresh cycle)
local FormatNumber = ns.UI_FormatNumber
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local COLORS = ns.UI_COLORS

local function ThemeTextHex(role)
    if ns.UI_GetTextRoleHex then
        return ns.UI_GetTextRoleHex(role)
    end
    if role == "Dim" then return "|cff888888" end
    if role == "Muted" then return "|cffaaaaaa" end
    return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
end

local function SemanticGoldHex()
    if ns.UI_GetSemanticGoldHex then
        return ns.UI_GetSemanticGoldHex()
    end
    return "|cffffcc00"
end

local function SemanticColorHex(color)
    if not color then return ThemeTextHex("Bright") end
    return format("|cff%02x%02x%02x", (color[1] or 1) * 255, (color[2] or 1) * 255, (color[3] or 1) * 255)
end

local function SemanticGoldRGB()
    if ns.UI_GetSemanticGoldColor then
        return ns.UI_GetSemanticGoldColor()
    end
    local g = COLORS.gold or { 1, 0.82, 0, 1 }
    return g[1], g[2], g[3], g[4] or 1
end

local function FormatParenBadge(innerColoredText)
    local muted = ThemeTextHex("Muted")
    return muted .. "(|r" .. innerColoredText .. muted .. ")|r"
end

-- Import pooling functions (performance: reuse frames instead of creating new ones)
local AcquireReputationRow = ns.UI_AcquireReputationRow
local ReleaseReputationRow = ns.UI_ReleaseReputationRow

local ReleaseReputationRowsFromSubtree = ns.UI_ReleaseReputationRowsFromSubtree
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Performance: Local function references
local format = string.format
local floor = math.floor

local pairs = pairs
local next = next
local table_wipe = table.wipe
local tinsert = table.insert

-- Import shared UI constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8
local ROW_HEIGHT = GetLayout().ROW_HEIGHT or 26
-- Row metric: UI_LAYOUT.TABLE.ROW_H.standard (SharedWidgets_TableKit list rows).
local REP_ROW_HEIGHT = (GetLayout().TABLE and GetLayout().TABLE.ROW_H.standard) or 30
local REP_ROW_GAP = (ns.UI_DataRowGap and ns.UI_DataRowGap()) or (ns.UI_LAYOUT and ns.UI_LAYOUT.dataRowGap) or 4
local ROW_SPACING = GetLayout().ROW_SPACING or 26
local HEADER_SPACING = GetLayout().HEADER_SPACING or 44
local SUBHEADER_SPACING = GetLayout().SUBHEADER_SPACING or 44
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
local PAGE_STACK = GetLayout().PAGE_STACK or {} -- standard tab rhythm (SharedWidgets_Layout)

-- REPUTATION ROW COLUMN MODEL (SharedWidgets_TableKit; defined + resolved once, base widths, no flex).
-- Leading columns (chevron, standing) anchor LEFT at their x; trailing columns (badge, marker, progress)
-- anchor from the row's RIGHT edge so they line up across indented sub-faction rows (row right edges
-- match); the flex name column spans between. Kit convention: text sits CELL_PAD_X inside its column.
local REP_ROW = {}
do
    local TK = ns.UI_TableKit
    assert(TK and GetLayout().TABLE, "SharedWidgets_TableKit.lua must load before ReputationUI.lua")
    local T = GetLayout().TABLE
    local pad, gap = T.CELL_PAD_X, T.COL_GAP
    REP_ROW.cols = {
        { key = "chevron",  width = GetLayout().COLLAPSE_EXPAND_BUTTON_SIZE or 22, align = "CENTER" },
        { key = "standing", width = 120 + pad * 2, align = "LEFT" },
        { key = "name",     width = 0, flex = 1,   align = "LEFT" },
        { key = "badge",    width = 220 + pad * 2, align = "LEFT" },
        { key = "marker",   width = 42,            align = "RIGHT" }, -- paragon / check icons left of the bar
        { key = "progress", width = 200,           align = "RIGHT" }, -- ApplyReputationRowProgressChrome bar
    }
    REP_ROW.widths, REP_ROW.offsets = {}, {}
    TK.ResolveWidths(REP_ROW.cols, nil, REP_ROW.widths, REP_ROW.offsets, pad, gap)
    local W = REP_ROW.widths
    REP_ROW.pad = pad
    REP_ROW.standingTextW = W[2] - pad * 2
    REP_ROW.badgeTextW = W[4] - pad * 2
    REP_ROW.progressW = W[6]
    REP_ROW.progressRight = pad                                      -- bar RIGHT inset
    local markerLeft = REP_ROW.progressRight + W[6] + gap + W[5]     -- from row right
    local badgeLeft = markerLeft + gap + W[4]
    REP_ROW.badgeLeftFromRight = badgeLeft - pad                     -- badge text LEFT, measured from row right
    REP_ROW.nameRightBadge = badgeLeft + gap + pad                   -- name text RIGHT inset (badge shown)
    REP_ROW.nameRightNoBadge = markerLeft + gap + pad                -- name text RIGHT inset (no badge)
end

-- REPUTATION FORMATTING & HELPERS

---Get standing name from standing ID
---@param standingID number Standing ID (1-8)
---@return string Standing name
local function GetStandingName(standingID)
    local standings = {
        [1] = FACTION_STANDING_LABEL1 or "Hated",
        [2] = FACTION_STANDING_LABEL2 or "Hostile",
        [3] = FACTION_STANDING_LABEL3 or "Unfriendly",
        [4] = FACTION_STANDING_LABEL4 or "Neutral",
        [5] = FACTION_STANDING_LABEL5 or "Friendly",
        [6] = FACTION_STANDING_LABEL6 or "Honored",
        [7] = FACTION_STANDING_LABEL7 or "Revered",
        [8] = FACTION_STANDING_LABEL8 or "Exalted",
    }
    return standings[standingID] or (ns.L and ns.L["UNKNOWN"]) or "Unknown"
end

---Get standing color (RGB) from standing ID
---@param standingID number Standing ID (1-8)
---@return number r, number g, number b
local function GetStandingColor(standingID)
    local colors = {
        [1] = {0.8, 0.13, 0.13},  -- Hated (dark red)
        [2] = {0.93, 0.4, 0.4},   -- Hostile (red)
        [3] = {1, 0.6, 0.2},      -- Unfriendly (orange)
        [4] = {1, 1, 0},          -- Neutral (yellow)
        [5] = {0, 1, 0},          -- Friendly (green)
        [6] = {0, 1, 0.59},       -- Honored (light green)
        [7] = {0, 1, 1},          -- Revered (cyan)
        [8] = {0.73, 0.4, 1},     -- Exalted (purple)
    }
    local color = colors[standingID] or {1, 1, 1}
    return color[1], color[2], color[3]
end

---Format reputation progress text
---@param current number Current value
---@param max number Max value
---@return string Formatted text
local function FormatReputationProgress(current, max)
    if current == 1 and max == 1 then
        return ThemeTextHex("Bright") .. ((ns.L and ns.L["REP_MAX"]) or "Max.") .. "|r"
    elseif max > 0 then
        return format("%s / %s", FormatNumber(current), FormatNumber(max))
    else
        return FormatNumber(current)
    end
end

---Compact standing label for per-character tooltip rows.
local function FormatReputationStandingLabel(rep)
    if not rep then return "?" end
    if rep.renown and rep.renown.level and rep.renown.level > 0 then
        local fmt = (ns.L and ns.L["REP_RENOWN_FORMAT"]) or "Renown %d"
        return string.format(fmt, rep.renown.level)
    end
    if rep.hasParagon and rep.paragon then
        return FormatReputationProgress(rep.paragon.current, rep.paragon.max)
    end
    if rep.friendship and rep.friendship.reactionText and rep.friendship.reactionText ~= "" then
        return rep.friendship.reactionText
    end
    if rep.friendship and rep.friendship.standing then
        return tostring(rep.friendship.standing)
    end
    if rep.standing and rep.standing.name and rep.standing.name ~= "" then
        if (rep.maxValue or 1) > 1 then
            return rep.standing.name .. " " .. FormatReputationProgress(rep.currentValue or 0, rep.maxValue or 1)
        end
        return rep.standing.name
    end
    return FormatReputationProgress(rep.currentValue or 0, rep.maxValue or 1)
end

local REP_TOOLTIP_CHARS_DEFAULT = 10
local REP_TOOLTIP_CHARS_SHIFT_MAX = 50

local function AppendReputationCharacterProgressLines(lines, allCharData)
    if not allCharData or #allCharData == 0 then return end
    local isShift = IsShiftKeyDown and IsShiftKeyDown() or false
    local limit = isShift and REP_TOOLTIP_CHARS_SHIFT_MAX or REP_TOOLTIP_CHARS_DEFAULT
    local rowCount = #allCharData
    local hiddenCount = math.max(0, rowCount - limit)

    table.insert(lines, { type = "spacer", height = 8 })
    local gr, gg, gb = SemanticGoldRGB()
    table.insert(lines, { text = (ns.L and ns.L["REP_CHARACTER_PROGRESS"]) or "Character Progress:", color = { gr, gg, gb } })

    local shown = 0
    for aci = 1, rowCount do
        if shown >= limit then break end
        local charData = allCharData[aci]
        local charReputation = charData.reputation
        local classFile = string.upper(charData.characterClass or "WARRIOR")
        local classColor = RAID_CLASS_COLORS[classFile] or { r = 1, g = 1, b = 1 }
        shown = shown + 1
        table.insert(lines, {
            left = (charData.characterName or "?") .. ":",
            right = FormatReputationStandingLabel(charReputation),
            leftColor = { classColor.r, classColor.g, classColor.b },
            rightColor = { 1, 1, 1 },
        })
    end

    if hiddenCount > 0 then
        if not isShift then
            table.insert(lines, { text = (ns.L and ns.L["TOOLTIP_HOLD_SHIFT"]) or "  Hold [Shift] for full list", color = { 0.5, 0.5, 0.5 } })
        else
            local moreFmt = (ns.L and ns.L["CURRENCY_TOOLTIP_MORE_CHARACTERS"]) or "+%d more characters"
            table.insert(lines, { text = string.format(moreFmt, hiddenCount), color = { 0.6, 0.6, 0.6 } })
        end
    end
end

---Logged-in character row key (GUID / roster aliases).
local function ResolveSessionCharacterKey(charLookup, characters)
    local sessionKey = ns.UI_GetSubsidiaryCharKey and ns.UI_GetSubsidiaryCharKey()
    if sessionKey and charLookup[sessionKey] then
        return sessionKey, charLookup[sessionKey]
    end
    local U = ns.Utilities
    local storage = U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(WarbandNexus)
    if storage and charLookup[storage] then
        return storage, charLookup[storage]
    end
    if storage and U and U.GetCanonicalCharacterKey then
        local canon = U:GetCanonicalCharacterKey(storage)
        if canon and charLookup[canon] then
            return canon, charLookup[canon]
        end
    end
    for ci = 1, #characters do
        local char = characters[ci]
        local charKey = ns.UI_GetCharKey and ns.UI_GetCharKey(char)
        if charKey and charLookup[charKey] then
            return charKey, charLookup[charKey]
        end
    end
    return nil, nil
end

local function FindCharReputationInMap(charDataMap, charKey)
    if not charDataMap or not charKey then return nil end
    local entry = charDataMap[charKey]
    if entry and entry.reputation then return entry.reputation end
    local U = ns.Utilities
    if U and U.GetCanonicalCharacterKey then
        local canon = U:GetCanonicalCharacterKey(charKey)
        if canon and canon ~= charKey then
            entry = charDataMap[canon]
            if entry and entry.reputation then return entry.reputation end
        end
    end
    for mapKey, mapEntry in pairs(charDataMap) do
        if mapEntry and mapEntry.reputation and U and U.GetCanonicalCharacterKey then
            local c1 = U:GetCanonicalCharacterKey(mapKey) or mapKey
            local c2 = U:GetCanonicalCharacterKey(charKey) or charKey
            if c1 == c2 then return mapEntry.reputation end
        end
    end
    return nil
end

---@param reputation table
---@return boolean baseMaxed
local function ComputeBaseReputationMaxed(reputation)
    local isParagon = reputation.hasParagon or false
    if isParagon then return true end
    local currentValue = reputation.currentValue or 0
    local maxValue = reputation.maxValue or 1
    if reputation.type == "renown" and reputation.renown then
        if reputation.renown.maxLevel and reputation.renown.maxLevel > 0 then
            return ((reputation.renown.level or 0) >= reputation.renown.maxLevel)
        elseif reputation.maxValue == 1 and currentValue >= 1 then
            return true
        end
    elseif reputation.type == "friendship" and reputation.friendship then
        if reputation.friendship.maxLevel and reputation.friendship.maxLevel > 0 then
            return ((reputation.friendship.level or 0) >= reputation.friendship.maxLevel)
        elseif reputation.maxValue == 1 and currentValue >= 1 then
            return true
        end
    elseif reputation.standingID == 8 then
        return (reputation.maxValue == 1 or currentValue >= maxValue)
    end
    return false
end

---Progress bar, paragon icon, checkmark (inline pooled bar â€” pre-MetricBar style).
---@return Frame|nil progressBg
---@param chromeOpts table|nil { showSplit, sessionRep, bestRep }
local function ApplyReputationRowProgressChrome(row, reputation, rowWidth)
    local currentValue = reputation.currentValue or 0
    local maxValue = reputation.maxValue or 1
    local isParagon = reputation.hasParagon or false
    local rewardPending = (reputation.paragon and reputation.paragon.hasRewardPending) or false
    local baseReputationMaxed = ComputeBaseReputationMaxed(reputation)

    local standingID = reputation.standingID or 4
    local hasRenown = (reputation.type == "renown") or false

    -- Drop MetricBar-era holder so pooled rows rebuild classic textures.
    if row._progressBar and row._progressBar.wrapper then
        if row._progressBar.wrapper.Hide then row._progressBar.wrapper:Hide() end
        row._progressBar = nil
    end
    if row.repMetricAmount then row.repMetricAmount:Hide() end

    if not row._progressBar then
        local pb = {}
        pb.bg = (ns.UI.Factory and ns.UI.Factory:CreateContainer(row, 200, 19, false))
            or CreateFrame("Frame", nil, row)
        pb.bg:SetFrameLevel(row:GetFrameLevel() + 10)

        pb.bgTexture = pb.bg:CreateTexture(nil, "BACKGROUND")
        pb.bgTexture:SetSnapToPixelGrid(false)
        pb.bgTexture:SetTexelSnappingBias(0)

        pb.fill = pb.bg:CreateTexture(nil, "ARTWORK")
        pb.fill:SetSnapToPixelGrid(false)
        pb.fill:SetTexelSnappingBias(0)

        local function MakeBorder()
            local t = pb.bg:CreateTexture(nil, "BORDER")
            t:SetTexture("Interface\\Buttons\\WHITE8x8")
            if ns.UI_SnapRuleTexture then ns.UI_SnapRuleTexture(t) end
            t:SetDrawLayer("BORDER", 0)
            return t
        end
        pb.borderTop = MakeBorder()
        pb.borderBottom = MakeBorder()
        pb.borderLeft = MakeBorder()
        pb.borderRight = MakeBorder()

        row._progressBar = pb
    end

    local pb = row._progressBar
    local barWidth, barHeight = REP_ROW.progressW, 19
    local borderInset = 1
    local fillInset = borderInset + 1
    local contentWidth = barWidth - (borderInset * 2)

    pb.bg:SetSize(barWidth, barHeight)
    pb.bg:ClearAllPoints()
    pb.bg:SetPoint("RIGHT", row, "RIGHT", -REP_ROW.progressRight, 0)
    pb.bg:Show()

    local bgColor = COLORS.bg
    if ns.UI_IsLightMode and ns.UI_IsLightMode() then
        bgColor = COLORS.surfaceRowOdd or COLORS.bg or bgColor
    else
        bgColor = COLORS.bg or { 0.042, 0.042, 0.055, 0.95 }
    end
    pb.bgTexture:ClearAllPoints()
    pb.bgTexture:SetPoint("TOPLEFT", pb.bg, "TOPLEFT", borderInset, -borderInset)
    pb.bgTexture:SetPoint("BOTTOMRIGHT", pb.bg, "BOTTOMRIGHT", -borderInset, borderInset)
    pb.bgTexture:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.8)

    local progress = 0
    if maxValue > 0 then
        progress = math.min(1, math.max(0, currentValue / maxValue))
    end
    if baseReputationMaxed and not isParagon then progress = 1 end

    local fillWidth = math.max((contentWidth - 2) * progress, 0.001)
    pb.fill:ClearAllPoints()
    pb.fill:SetPoint("LEFT", pb.bg, "LEFT", fillInset, 0)
    pb.fill:SetPoint("TOP", pb.bg, "TOP", 0, -fillInset)
    pb.fill:SetPoint("BOTTOM", pb.bg, "BOTTOM", 0, fillInset)
    pb.fill:SetWidth(fillWidth)
    pb.fill:Show()

    if baseReputationMaxed and not isParagon then
        pb.fill:SetColorTexture(0, 0.8, 0, 1)
    elseif isParagon then
        pb.fill:SetColorTexture(1, 0.4, 1, 1)
    elseif (not hasRenown and reputation.type ~= "friendship") and standingID then
        local standingColors = {
            [1] = {0.8, 0.13, 0.13}, [2] = {0.8, 0.13, 0.13},
            [3] = {0.75, 0.27, 0},    [4] = {0.9, 0.7, 0},
            [5] = {0, 0.6, 0.1},      [6] = {0, 0.6, 0.1},
            [7] = {0, 0.6, 0.1},      [8] = {0, 0.6, 0.1},
        }
        local c = standingColors[standingID] or {0.9, 0.7, 0}
        pb.fill:SetColorTexture(c[1], c[2], c[3], 1)
    else
        local goldColor = COLORS.gold or {1, 0.82, 0, 1}
        pb.fill:SetColorTexture(goldColor[1], goldColor[2], goldColor[3], goldColor[4] or 1)
    end

    local borderColor = COLORS.borderLight or COLORS.border or COLORS.accent
    local br, bgc, bb = borderColor[1], borderColor[2], borderColor[3]
    local ba = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.88 or 0.58

    -- Border textures opt out of pixel-grid snapping, so size them in physical pixels.
    local px = (ns.GetPixelScale and ns.GetPixelScale(pb.bg)) or 1

    pb.borderTop:ClearAllPoints()
    pb.borderTop:SetPoint("TOPLEFT", pb.bg, "TOPLEFT", 0, 0)
    pb.borderTop:SetPoint("TOPRIGHT", pb.bg, "TOPRIGHT", 0, 0)
    pb.borderTop:SetHeight(px)
    pb.borderTop:SetVertexColor(br, bgc, bb, ba)

    pb.borderBottom:ClearAllPoints()
    pb.borderBottom:SetPoint("BOTTOMLEFT", pb.bg, "BOTTOMLEFT", 0, 0)
    pb.borderBottom:SetPoint("BOTTOMRIGHT", pb.bg, "BOTTOMRIGHT", 0, 0)
    pb.borderBottom:SetHeight(px)
    pb.borderBottom:SetVertexColor(br, bgc, bb, ba)

    pb.borderLeft:ClearAllPoints()
    pb.borderLeft:SetPoint("TOPLEFT", pb.bg, "TOPLEFT", 0, -px)
    pb.borderLeft:SetPoint("BOTTOMLEFT", pb.bg, "BOTTOMLEFT", 0, px)
    pb.borderLeft:SetWidth(px)
    pb.borderLeft:SetVertexColor(br, bgc, bb, ba)

    pb.borderRight:ClearAllPoints()
    pb.borderRight:SetPoint("TOPRIGHT", pb.bg, "TOPRIGHT", 0, -px)
    pb.borderRight:SetPoint("BOTTOMRIGHT", pb.bg, "BOTTOMRIGHT", 0, px)
    pb.borderRight:SetWidth(px)
    pb.borderRight:SetVertexColor(br, bgc, bb, ba)

    local progressBg = pb.bg

    if isParagon then
        local hasReward = rewardPending
        local iconCreated = false
        local CreateParagonIcon = ns.UI_CreateParagonIcon
        if CreateParagonIcon then
            if not row.paragonFrame then
                local success, pFrame = pcall(CreateParagonIcon, row, 18, hasReward)
                if success and pFrame then
                    row.paragonFrame = pFrame
                    row.paragonFrame:EnableMouse(true)
                end
            end
            if row.paragonFrame then
                row.paragonFrame:ClearAllPoints()
                row.paragonFrame:SetPoint("RIGHT", progressBg or row, progressBg and "LEFT" or "RIGHT", -24, 0)
                row.paragonFrame:SetScript("OnEnter", function(self)
                    local tooltipData = {
                        type = "custom",
                        icon = "Interface\\Icons\\INV_Misc_Bag_10",
                        title = (ns.L and ns.L["REP_PARAGON_TITLE"]) or "Paragon Reputation",
                        lines = {}
                    }
                    if hasReward then
                        table.insert(tooltipData.lines, { text = (ns.L and ns.L["REP_REWARD_AVAILABLE"]) or "Reward available!", color = { 0, 1, 0 } })
                    else
                        table.insert(tooltipData.lines, { text = (ns.L and ns.L["REP_CONTINUE_EARNING"]) or "Continue earning reputation for rewards", color = { 0.8, 0.8, 0.8 } })
                    end
                    if reputation.paragon then
                        table.insert(tooltipData.lines, { text = string.format((ns.L and ns.L["REP_CYCLES_FORMAT"]) or "Cycles: %d", reputation.paragon.completedCycles or 0), color = { 0.8, 0.8, 0.8 } })
                    end
                    ns.TooltipService:Show(self, tooltipData)
                end)
                row.paragonFrame:SetScript("OnLeave", function() ns.TooltipService:Hide() end)
                row.paragonFrame:Show()
                iconCreated = true
            end
        end
        if not iconCreated then
            if not row.paragonFrame then
                row.paragonFrame = CreateIcon(row, "Interface\\Icons\\INV_Misc_Bag_10", 18, false, nil, true)
                if row.paragonFrame then row.paragonFrame:EnableMouse(true) end
            end
            if row.paragonFrame then
                row.paragonFrame:ClearAllPoints()
                row.paragonFrame:SetPoint("RIGHT", progressBg or row, progressBg and "LEFT" or "RIGHT", -24, 0)
                if row.paragonFrame.texture then
                    local dim = not rewardPending
                    row.paragonFrame.texture:SetVertexColor(dim and 0.5 or 1, dim and 0.5 or 1, dim and 0.5 or 1, 1)
                end
                row.paragonFrame:SetScript("OnEnter", function(self)
                    local tooltipData = {
                        type = "custom",
                        icon = "Interface\\Icons\\INV_Misc_Bag_10",
                        title = (ns.L and ns.L["REP_PARAGON_TITLE"]) or "Paragon Reputation",
                        lines = {}
                    }
                    if hasReward then
                        table.insert(tooltipData.lines, { text = (ns.L and ns.L["REP_REWARD_AVAILABLE"]) or "Reward available!", color = { 0, 1, 0 } })
                    else
                        table.insert(tooltipData.lines, { text = (ns.L and ns.L["REP_CONTINUE_EARNING"]) or "Continue earning reputation for rewards", color = { 0.8, 0.8, 0.8 } })
                    end
                    if reputation.paragon then
                        table.insert(tooltipData.lines, { text = string.format((ns.L and ns.L["REP_PROGRESS_HEADER"]) or "Progress: %d / %d", reputation.paragon.current or 0, reputation.paragon.max or 10000), color = { 0.8, 0.8, 0.8 } })
                        table.insert(tooltipData.lines, { text = string.format((ns.L and ns.L["REP_CYCLES_FORMAT"]) or "Cycles: %d", reputation.paragon.completedCycles or 0), color = { 0.8, 0.8, 0.8 } })
                    end
                    ns.TooltipService:Show(self, tooltipData)
                end)
                row.paragonFrame:SetScript("OnLeave", function() ns.TooltipService:Hide() end)
                row.paragonFrame:Show()
            end
        end
    else
        if row.paragonFrame then row.paragonFrame:Hide() end
    end

    if baseReputationMaxed then
        if not row.checkFrame then
            row.checkFrame = CreateIcon(row, "Interface\\RaidFrame\\ReadyCheck-Ready", 16, false, nil, true)
            if row.checkFrame and row.checkFrame.texture then
                ns.UI_SetIcon(row.checkFrame.texture, "status_ok")
            end
        end
        row.checkFrame:ClearAllPoints()
        row.checkFrame:SetPoint("RIGHT", progressBg or row, progressBg and "LEFT" or "RIGHT", -4, 0)
        row.checkFrame:Show()
    else
        if row.checkFrame then row.checkFrame:Hide() end
    end

    if progressBg then
        if not row.progressText then
            row.progressText = FontManager:CreateBarOverlayFontString(progressBg, "OVERLAY")
            if not row.progressText then
                row.progressText = FontManager:CreateFontString(progressBg, "small", "OVERLAY")
                if ns.UI_ApplyFontStyleForRole then
                    ns.UI_ApplyFontStyleForRole(row.progressText, "small", { barOverlay = true })
                end
            end
            row.progressText:SetJustifyH("CENTER")
            row.progressText:SetJustifyV("MIDDLE")
        end
        row.progressText:SetParent(progressBg)
        row.progressText:ClearAllPoints()
        row.progressText:SetPoint("CENTER", progressBg, "CENTER", 0, 0)
        row.progressText:SetText(FormatReputationProgress(currentValue, maxValue))
        ns.UI_SetTextColorRole(row.progressText, "Bright")
        row.progressText:Show()
    end

    return progressBg
end

---Check if reputation matches search text
---@param reputation table Reputation data
---@param searchText string Search text (lowercase)
---@return boolean matches
local function ReputationMatchesSearch(reputation, searchText)
    if not searchText then
        return true
    end
    if issecretvalue and issecretvalue(searchText) then
        return true
    end
    if searchText == "" then
        return true
    end
    
    local name = SafeLower(reputation.name)
    
    return name:find(searchText, 1, true)
end

-- FILTERED VIEW AGGREGATION

-- Phase 2.4: Cache for filtered search results
local cachedSearchText = nil
local cachedFilteredResults = {} -- [headerName|scope|searchText] = filteredFactionList

-- Aggregate snapshot cache (header groups + AW/CB split); invalidated on WN_REPUTATION_*.
local charLookupScratch = {}
local repAggregateCache = {
    key = nil,
    aggregatedHeaders = nil,
    accountWideHeaders = nil,
    characterBasedHeaders = nil,
}

local function InvalidateRepDrawCaches()
    repAggregateCache.key = nil
    repAggregateCache.aggregatedHeaders = nil
    repAggregateCache.accountWideHeaders = nil
    repAggregateCache.characterBasedHeaders = nil
    if table_wipe then
        table_wipe(cachedFilteredResults)
    else
        for k in pairs(cachedFilteredResults) do
            cachedFilteredResults[k] = nil
        end
    end
    cachedSearchText = nil
end

---@param characters table
---@return string
local function GetReputationAggregateCacheKey(characters)
    local db = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.reputationData
    local parts = {
        tostring(db and db.lastScan or 0),
        tostring(db and db.version or 0),
        tostring(#characters),
    }
    for ci = 1, #characters do
        local char = characters[ci]
        local charKey = ns.UI_GetCharKey and ns.UI_GetCharKey(char)
        parts[#parts + 1] = charKey or ""
    end
    local cacheHeaders = WarbandNexus.GetReputationHeaders and WarbandNexus:GetReputationHeaders() or {}
    parts[#parts + 1] = tostring(#cacheHeaders)
    local sessionKey = ns.UI_GetSubsidiaryCharKey and ns.UI_GetSubsidiaryCharKey()
    parts[#parts + 1] = "sk:" .. (sessionKey or "")
    return table.concat(parts, "\031")
end

---@param aggregatedHeaders table
---@return table accountWideHeaders, table characterBasedHeaders
local function SplitAggregatedHeaders(aggregatedHeaders)
    local accountWideHeaders = {}
    local characterBasedHeaders = {}
    local seenInAccountWide = {}

    for ahi = 1, #aggregatedHeaders do
        local headerData = aggregatedHeaders[ahi]
        local awFactions = {}
        local cbFactions = {}

        local hdrFacs = headerData.factions
        for fi = 1, #hdrFacs do
            local faction = hdrFacs[fi]
            local isAW = faction.isAccountWide or (faction.data and faction.data.isAccountWide)
            if isAW == nil and faction.factionID and C_Reputation and C_Reputation.IsAccountWideReputation then
                isAW = C_Reputation.IsAccountWideReputation(faction.factionID) or false
            end
            if isAW == nil then isAW = false end

            local fid = faction.factionID or faction.data and faction.data.factionID
            if isAW then
                tinsert(awFactions, faction)
                if fid then seenInAccountWide[fid] = true end
            elseif not (fid and seenInAccountWide[fid]) then
                tinsert(cbFactions, faction)
            end
        end

        if #awFactions > 0 then
            tinsert(accountWideHeaders, { name = headerData.name, factions = awFactions })
        end
        if #cbFactions > 0 then
            tinsert(characterBasedHeaders, { name = headerData.name, factions = cbFactions })
        end
    end

    return accountWideHeaders, characterBasedHeaders
end

---Compare two reputation values to determine which is higher
---@param rep1 table First reputation data
---@param rep2 table Second reputation data
---@return boolean true if rep1 is higher than rep2
local function IsReputationHigher(rep1, rep2)
    -- Priority: Paragon > Renown > Standing > CurrentValue
    
    -- Check Paragon first (highest priority)
    local hasParagon1 = (rep1.paragonValue and rep1.paragonThreshold) and true or false
    local hasParagon2 = (rep2.paragonValue and rep2.paragonThreshold) and true or false
    
    if hasParagon1 and not hasParagon2 then
        return true
    elseif hasParagon2 and not hasParagon1 then
        return false
    elseif hasParagon1 and hasParagon2 then
        -- Both have paragon, compare paragon values
        if rep1.paragonValue ~= rep2.paragonValue then
            return rep1.paragonValue > rep2.paragonValue
        end
    end
    
    -- Check Renown level
    local renown1 = (rep1.renown and rep1.renown.level) or 0
    local renown2 = (rep2.renown and rep2.renown.level) or 0
    
    if renown1 ~= renown2 then
        return renown1 > renown2
    end
    
    -- Check Standing
    local standing1 = rep1.standingID or 0
    local standing2 = rep2.standingID or 0
    
    if standing1 ~= standing2 then
        return standing1 > standing2
    end
    
    -- Finally compare current value
    local value1 = rep1.currentValue or 0
    local value2 = rep2.currentValue or 0
    
    return value1 > value2
end

---Per-faction half of AggregateReputations: best character + allCharData for each faction.
---onlyFactionIDs (set) limits it to those factions -- the row patch path re-runs it for the factions
---a scan changed (2026-10-22).
---@param cachedFactions table Hydrated rows (GetAllReputations / GetReputationsForFactions)
---@param characters table Tracked characters
---@param onlyFactionIDs table|nil [factionID] = true
---@return table factionMap [factionID] = {data, characterKey, characterName, characterClass, allCharData, ...}
local function BuildReputationFactionMap(cachedFactions, characters, onlyFactionIDs)
    -- Collect all unique faction IDs and their best reputation
    local factionMap = {} -- [factionID] = {data, characterKey, characterName, characterClass, allCharData}
    
    -- Build character lookup table (SavedVariables row key = guid or Name-Realm; matches currency/cache writes).
    local charLookup = charLookupScratch
    if table_wipe then
        table_wipe(charLookup)
    else
        for k in pairs(charLookup) do
            charLookup[k] = nil
        end
    end
    local U = ns.Utilities
    for ci = 1, #characters do
        local char = characters[ci]
        local charKey = ns.UI_GetCharKey and ns.UI_GetCharKey(char)
        if charKey then
            charLookup[charKey] = char
            if U and U.GetCanonicalCharacterKey then
                local canon = U:GetCanonicalCharacterKey(charKey)
                if canon and canon ~= charKey then
                    charLookup[canon] = char
                end
            end
        end
    end
    
    local function BuildReputationObject(cachedData)
        return {
            -- Core
            factionID = cachedData.factionID,  -- Need this for tooltip matching
            name = cachedData.name,
            description = cachedData.description or "",
            iconTexture = cachedData.icon,
            parentFactionID = cachedData.parentFactionID,
            
            -- Classification
            type = cachedData.type,
            isHeader = cachedData.isHeader or false,
            isHeaderWithRep = cachedData.isHeaderWithRep or false,
            isAccountWide = cachedData.isAccountWide or false,
            parentHeaders = cachedData.parentHeaders or {},
            
            -- Standing
            standingID = cachedData.standingID,
            standing = {
                name = cachedData.standingName,
                color = cachedData.standingColor,
                id = cachedData.standingID,
            },
            
            -- Progress (already normalized in Processor)
            -- Processor sets currentValue/maxValue correctly for all types
            currentValue = cachedData.currentValue or 0,
            maxValue = cachedData.maxValue or 1,
            progressPercent = ((cachedData.currentValue or 0) / (cachedData.maxValue or 1)) * 100,
            
            -- Paragon state (if applicable)
            hasParagon = cachedData.hasParagon or false,
            
            -- Type-specific data
            friendship = cachedData.friendship,
            renown = cachedData.renown,
            paragon = cachedData.paragon,
            
            -- Legacy fields (for compatibility)
            isMajorFaction = (cachedData.type == "renown"),
            isFriendship = (cachedData.type == "friendship"),
            isRenown = (cachedData.type == "renown"),
            
            -- Metadata
            lastUpdated = cachedData._scanTime or time(),
            
            -- Preserve _scanIndex for Blizzard UI ordering
            _scanIndex = cachedData._scanIndex or 99999,
        }
    end
    
    -- PHASE 1: Collect ALL character data for each faction
    -- Build: factionID -> {charKey -> {reputation, char}}
    local factionCharacterMap = {}
    
    for cfi = 1, #cachedFactions do
        local cachedData = cachedFactions[cfi]
        local factionID = cachedData.factionID
        
        -- Only process factions with rep (skip pure organizational headers)
        if not (cachedData.isHeader and not cachedData.isHeaderWithRep)
            and (not onlyFactionIDs or onlyFactionIDs[factionID]) then
            
            if cachedData.isAccountWide then
                local reputation = BuildReputationObject(cachedData)
                local sessionKey, sessionChar = ResolveSessionCharacterKey(charLookup, characters)

                factionMap[factionID] = {
                    data = reputation,
                    characterKey = sessionKey or ((ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account-Wide"),
                    characterName = sessionChar and sessionChar.name or ((ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account"),
                    characterRealm = sessionChar and (sessionChar.realm or "") or "",
                    characterClass = sessionChar and (sessionChar.classFile or sessionChar.class) or "WARRIOR",
                    characterLevel = sessionChar and sessionChar.level or 80,
                    isAccountWide = true,
                    allCharData = {},
                    sessionReputation = reputation,
                    bestReputation = reputation,
                    repProgressSplit = sessionChar ~= nil,
                }
            else
                -- CHARACTER-SPECIFIC: Collect data for this character
                local charKey = cachedData._characterKey or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
                local char = charLookup[charKey]
                if not char and U and U.GetCanonicalCharacterKey then
                    char = charLookup[U:GetCanonicalCharacterKey(charKey) or ""]
                end
                
                if char then
                    local reputation = BuildReputationObject(cachedData)
                    
                    -- NOTE: No search filter here â€” filtering happens in UI rendering
                    if not factionCharacterMap[factionID] then
                        factionCharacterMap[factionID] = {}
                    end
                    
                    factionCharacterMap[factionID][charKey] = {
                        reputation = reputation,
                        char = char,
                        charKey = charKey,
                    }
                end
            end
        end
    end
    
    -- PHASE 2: For each faction, find HIGHEST progress character and build allCharData
    local sessionKey, sessionChar = ResolveSessionCharacterKey(charLookup, characters)

    for factionID, charDataMap in pairs(factionCharacterMap) do
        local bestCharKey = nil
        local bestReputation = nil
        local bestChar = nil
        
        local allCharData = {}
        
        -- Iterate all characters for this faction
        for charKey, charData in pairs(charDataMap) do
            local reputation = charData.reputation
            local char = charData.char
            
            -- Add to allCharData array
            table.insert(allCharData, {
                characterName = char.name,
                characterRealm = char.realm or "",
                characterClass = char.classFile or char.class,
                characterLevel = char.level,
                reputation = reputation,
            })
            
            -- Check if this is the best character (highest progress)
            -- Use IsReputationHigher() for proper comparison (handles Renown, Paragon, Friendship, etc.)
            if not bestReputation or IsReputationHigher(reputation, bestReputation) then
                bestCharKey = charKey
                bestReputation = reputation
                bestChar = char
            end
        end
        
        -- Sort allCharData by reputation progress (highest first)
        -- Use IsReputationHigher() for consistent sorting
        table.sort(allCharData, function(a, b)
            return IsReputationHigher(a.reputation, b.reputation)
        end)
        
        -- Create factionMap entry with BEST character as primary
        if bestCharKey and bestReputation and bestChar then
            local resolvedAW = (bestReputation and bestReputation.isAccountWide) or false
            local sessionReputation = FindCharReputationInMap(charDataMap, sessionKey) or bestReputation

            factionMap[factionID] = {
                data = bestReputation,
                characterKey = resolvedAW and ((ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account-Wide") or bestCharKey,
                characterName = resolvedAW and ((ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account") or bestChar.name,
                characterRealm = resolvedAW and "" or (bestChar.realm or ""),
                characterClass = resolvedAW and "WARRIOR" or (bestChar.classFile or bestChar.class),
                characterLevel = resolvedAW and 80 or bestChar.level,
                isAccountWide = resolvedAW,
                allCharData = resolvedAW and {} or allCharData,
                sessionReputation = sessionReputation,
                bestReputation = bestReputation,
                repProgressSplit = not resolvedAW,
            }
        end
    end

    return factionMap
end

---Aggregate reputations across all characters (find highest for each faction)
---v2.0.0: Reads from NEW ReputationCacheService with normalized data
---@param characters table List of character data
---@param factionMetadata table Faction metadata (DEPRECATED, for icons only)
---@param reputationSearchText string Search filter
---@return table List of {headerName, factions={factionID, data, characterKey, characterName, characterClass, isAccountWide}}
local function AggregateReputations(characters, factionMetadata, reputationSearchText)
    -- v2.0.0: Read from NEW ReputationCacheService (normalized data)
    local cachedFactions = WarbandNexus:GetAllReputations() or {}
    
    if #cachedFactions == 0 then
        return {}
    end

    local factionMap = BuildReputationFactionMap(cachedFactions, characters)
    
    -- v2.0.0: build parent-child relationships before header groups
    local childCount = 0
    
    for factionID, entry in pairs(factionMap) do
        local parentID = entry.data.parentFactionID
        if parentID then
            childCount = childCount + 1
            -- Type normalization - ensure both are numbers
            local numParentID = tonumber(parentID) or parentID
            local numFactionID = tonumber(factionID) or factionID
            
            -- Try both number and string keys (factionMap might use either)
            local parentEntry = factionMap[numParentID] or factionMap[tostring(numParentID)]
            
            if parentEntry then
                -- This faction is a child of parentID
                if not parentEntry.subfactions then
                    parentEntry.subfactions = {}
                end
                table.insert(parentEntry.subfactions, entry)
            end
        end
    end
    
    -- Sort subfactions by _scanIndex (Blizzard order), NOT alphabetically
    for factionID, entry in pairs(factionMap) do
        if entry.subfactions and #entry.subfactions > 0 then
            table.sort(entry.subfactions, function(a, b)
                local indexA = (a.data and a.data._scanIndex) or 99999
                local indexB = (b.data and b.data._scanIndex) or 99999
                return indexA < indexB
            end)
        end
    end
    
    -- v2.0.0: Group by expansion headers from NEW cache system
    local headerGroups = {}
    local headerOrder = {}
    local seenHeaders = {}
    local headerFactionLists = {} -- Use ARRAYS to preserve order, not sets
    
    -- Get headers from NEW cache (v2.0.0)
    local cacheHeaders = {}
    if WarbandNexus.GetReputationHeaders then
        cacheHeaders = WarbandNexus:GetReputationHeaders() or {}
    end
    
    -- Fallback to old global headers if new cache not ready
    local globalHeaders = (#cacheHeaders > 0) and cacheHeaders or (WarbandNexus.db.global.reputationHeaders or {})
    
    for ghi = 1, #globalHeaders do
        local headerData = globalHeaders[ghi]
        if headerData and headerData.name then
            
                if not seenHeaders[headerData.name] then
                    seenHeaders[headerData.name] = true
                    table.insert(headerOrder, headerData.name)
                    headerFactionLists[headerData.name] = {}  -- Array, not set
                end
                
                -- Add factions in ORDER, avoiding duplicates
                local existingFactions = {}
                local hflExisting = headerFactionLists[headerData.name]
                for fii = 1, #hflExisting do
                    local fid = hflExisting[fii]
                    -- Convert to number for consistent comparison
                    local numFid = tonumber(fid) or fid
                    existingFactions[numFid] = true
                end
                
            local hdrFactions = headerData.factions or {}
            for fai = 1, #hdrFactions do
                local factionID = hdrFactions[fai]
                -- Convert to number for consistent comparison
                local numFactionID = tonumber(factionID) or factionID
                if not existingFactions[numFactionID] then
                    table.insert(headerFactionLists[headerData.name], numFactionID)
                    existingFactions[numFactionID] = true
                end
            end
        end
    end
    
    -- Build header groups (preserve order from factionLists)
    for hoi = 1, #headerOrder do
        local headerName = headerOrder[hoi]
        local headerFactions = {}
        
        -- Iterate in ORDER (not random key-value pairs)
        local hflOrdered = headerFactionLists[headerName]
        for fii = 1, #hflOrdered do
            local factionID = hflOrdered[fii]
            -- Ensure consistent type for lookup
            local numFactionID = tonumber(factionID) or factionID
            local factionData = factionMap[numFactionID]
            
            -- Add if:
            -- 1. Top-level (no parent) OR
            -- 2. HeaderWithRep (can be both parent AND visible row)
            if factionData and (not factionData.data.parentFactionID or factionData.data.isHeaderWithRep) then
                table.insert(headerFactions, {
                    factionID = numFactionID,
                    data = factionData.data,
                    characterKey = factionData.characterKey,
                    characterName = factionData.characterName,
                    characterRealm = factionData.characterRealm,
                    characterClass = factionData.characterClass,
                    characterLevel = factionData.characterLevel,
                    isAccountWide = factionData.isAccountWide,
                    subfactions = factionData.subfactions,  -- NOW populated (built above!)
                    allCharData = factionData.allCharData or {},
                    sessionReputation = factionData.sessionReputation,
                    bestReputation = factionData.bestReputation or factionData.data,
                    repProgressSplit = factionData.repProgressSplit,
                })
            end
        end
        
        -- Sort by _scanIndex (Blizzard API order), NOT alphabetically
        table.sort(headerFactions, function(a, b)
            local indexA = (a.data and a.data._scanIndex) or 99999
            local indexB = (b.data and b.data._scanIndex) or 99999
            return indexA < indexB
        end)
        
        if #headerFactions > 0 then
            headerGroups[headerName] = {
                name = headerName,
                factions = headerFactions,
            }
        end
    end
    
    -- Convert to ordered list
    local result = {}
    for hoi = 1, #headerOrder do
        local headerName = headerOrder[hoi]
        if headerGroups[headerName] then
            table.insert(result, headerGroups[headerName])
        end
    end
    
    return result
end

---@param characters table
---@param factionMetadata table
---@return table aggregatedHeaders, table accountWideHeaders, table characterBasedHeaders
local function GetReputationAggregateSnapshot(characters, factionMetadata)
    local cacheKey = GetReputationAggregateCacheKey(characters)
    if repAggregateCache.key == cacheKey and repAggregateCache.aggregatedHeaders then
        return repAggregateCache.aggregatedHeaders,
            repAggregateCache.accountWideHeaders,
            repAggregateCache.characterBasedHeaders
    end

    local aggregatedHeaders = AggregateReputations(characters, factionMetadata)
    local accountWideHeaders, characterBasedHeaders = SplitAggregatedHeaders(aggregatedHeaders)

    repAggregateCache.key = cacheKey
    repAggregateCache.aggregatedHeaders = aggregatedHeaders
    repAggregateCache.accountWideHeaders = accountWideHeaders
    repAggregateCache.characterBasedHeaders = characterBasedHeaders

    return aggregatedHeaders, accountWideHeaders, characterBasedHeaders
end

---Truncate text if it's too long
---@param text string Text to truncate
---@param maxLength number Maximum length before truncation
---@return string Truncated text
local function TruncateText(text, maxLength)
    if not text then return "" end
    if string.len(text) <= maxLength then
        return text
    end
    return string.sub(text, 1, maxLength - 3) .. "..."
end

-- REPUTATION ROW RENDERING

---Create a single reputation row with progress bar
---PERFORMANCE: Uses pooled rows with lazy child creation (no frame leaks)
---ANIMATION: Supports staggered fade-in via centralized ApplyStaggerAnimation
---@param parent Frame Parent frame
---@param reputation table Reputation data
---@param factionID number Faction ID
---@param rowIndex number Row index for alternating colors
---@param indent number Left indent
---@param rowWidth number Row width
---@param yOffset number Y position
---@param subfactions table|nil Optional subfactions for expandable rows
---@param IsExpanded function Function to check expand state
---@param ToggleExpand function Function to toggle expand state
---@param characterInfo table|nil Optional {name, class, level, isAccountWide} for filtered view
---@return number newYOffset
---@return boolean|nil isExpanded
local function CreateReputationRow(parent, reputation, factionID, rowIndex, indent, rowWidth, yOffset, subfactions, IsExpanded, ToggleExpand, characterInfo)
    -- PERFORMANCE: Acquire from pool instead of creating new frames every refresh
    local row = AcquireReputationRow(parent, rowWidth, REP_ROW_HEIGHT)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", indent, -yOffset)
    
    -- Alternating background (centralized helper)
    ns.UI.Factory:ApplyRowBackground(row, rowIndex)
    
    local isExpanded = false
    local hasSubfactions = subfactions and #subfactions > 0
    
    if hasSubfactions then
        local collapseKey = "rep-subfactions-" .. factionID
        isExpanded = IsExpanded(collapseKey, false)
        
        -- Lazy create collapse button (reused across pool cycles)
        if not row.collapseBtn then
            row.collapseBtn = ns.UI_CreateCollapseExpandControl(row, isExpanded, { enableMouse = true })
        end

        row.collapseBtn:ClearAllPoints()
        row.collapseBtn:SetPoint("LEFT", row, "LEFT", REP_ROW.offsets[1], 0)
        ns.UI_CollapseExpandSetState(row.collapseBtn, isExpanded)

        -- Click handlers (toggle subfaction visibility)
        local function onSubfactionToggle()
            isExpanded = not isExpanded
            ns.UI_CollapseExpandSetState(row.collapseBtn, isExpanded)
            ToggleExpand(collapseKey, isExpanded)
        end
        
        row.collapseBtn:SetScript("OnClick", onSubfactionToggle)
        row:SetScript("OnClick", onSubfactionToggle)
        row.collapseBtn:SetFrameLevel((row:GetFrameLevel() or 0) + 25)
        row.collapseBtn:Show()
    end
    
    local standingWord = ""
    local standingNumber = ""
    local standingColorCode = ""
    
    -- PRIORITY 1: Friendship rank name (e.g., "Mastermind", "Good Friend")
    if reputation.friendship and reputation.friendship.reactionText then
        standingWord = reputation.friendship.reactionText
        standingColorCode = SemanticGoldHex()
    -- PRIORITY 2: Renown level (e.g., "Renown 25")
    elseif reputation.renown and reputation.renown.level and reputation.renown.level > 0 then
        standingWord = (ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown"
        standingNumber = tostring(reputation.renown.level)
        standingColorCode = SemanticGoldHex()
    -- PRIORITY 3: Friendship level (e.g., "Level 5")
    elseif reputation.friendship and reputation.friendship.level and reputation.friendship.level > 0 then
        standingWord = LEVEL or "Level"
        standingNumber = tostring(reputation.friendship.level)
        standingColorCode = SemanticGoldHex()
    -- PRIORITY 4: Classic standing (e.g., "Exalted", "Revered")
    elseif reputation.standing and reputation.standing.name then
        standingWord = reputation.standing.name
        local c = reputation.standing.color
        if c then
            standingColorCode = format("|cff%02x%02x%02x", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255)
        else
            standingColorCode = ThemeTextHex("Bright")
        end
    -- FALLBACK: Unknown
    else
        standingWord = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
        standingColorCode = SemanticColorHex(COLORS.red)
    end
    
    local textStartOffset = (hasSubfactions and REP_ROW.offsets[2] or REP_ROW.offsets[1]) + REP_ROW.pad

    if standingWord ~= "" then
        -- Standing text
        if not row.standingText then
            row.standingText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.standingText:SetJustifyH("LEFT")
            row.standingText:SetWidth(REP_ROW.standingTextW)
        end
        row.standingText:ClearAllPoints()
        row.standingText:SetPoint("LEFT", textStartOffset, 0)
        local fullStandingText = standingWord
        if standingNumber ~= "" then
            fullStandingText = standingWord .. " " .. standingNumber
        end
        row.standingText:SetText(standingColorCode .. fullStandingText .. "|r")
        row.standingText:Show()
        
        -- Separator
        if not row.separator then
            row.separator = FontManager:CreateFontString(row, "body", "OVERLAY")
        end
        row.separator:ClearAllPoints()
        row.separator:SetPoint("LEFT", row.standingText, "RIGHT", REP_ROW.pad, 0)
        row.separator:SetText(ThemeTextHex("Dim") .. "-|r")
        row.separator:Show()
        
        -- Faction Name (after separator)
        if not row.nameText then
            row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)
            row.nameText:SetNonSpaceWrap(false)
            row.nameText:SetMaxLines(1)
        end
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", row.separator, "RIGHT", REP_ROW.pad, 0)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -(characterInfo and REP_ROW.nameRightBadge or REP_ROW.nameRightNoBadge), 0)
        row.nameText:SetText(reputation.name or ((ns.L and ns.L["REP_UNKNOWN_FACTION"]) or "Unknown Faction"))
        ns.UI_SetTextColorRole(row.nameText, "Bright")
        row.nameText:Show()
    else
        -- No standing: hide standing/separator, show name directly
        if row.standingText then row.standingText:Hide() end
        if row.separator then row.separator:Hide() end
        
        if not row.nameText then
            row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)
            row.nameText:SetNonSpaceWrap(false)
            row.nameText:SetMaxLines(1)
        end
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", textStartOffset, 0)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -(characterInfo and REP_ROW.nameRightBadge or REP_ROW.nameRightNoBadge), 0)
        row.nameText:SetText(reputation.name or ((ns.L and ns.L["REP_UNKNOWN_FACTION"]) or "Unknown Faction"))
        ns.UI_SetTextColorRole(row.nameText, "Bright")
        row.nameText:Show()
    end
    
    if characterInfo then
        if not row.badgeText then
            row.badgeText = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.badgeText:SetJustifyH("LEFT")
            row.badgeText:SetWidth(REP_ROW.badgeTextW)
        end
        row.badgeText:ClearAllPoints()
        row.badgeText:SetPoint("LEFT", row, "RIGHT", -REP_ROW.badgeLeftFromRight, 0)
        
        if characterInfo.isAccountWide and not characterInfo.repProgressSplit then
            local label = ((ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account-Wide")
            row.badgeText:SetText(FormatParenBadge(SemanticColorHex(COLORS.green) .. label .. "|r"))
        elseif characterInfo.name then
            local classColor = RAID_CLASS_COLORS[characterInfo.class] or {r=1, g=1, b=1}
            local classHex = format("%02x%02x%02x", classColor.r*255, classColor.g*255, classColor.b*255)
            local inner = "|cff" .. classHex .. characterInfo.name
            if characterInfo.realm and characterInfo.realm ~= "" then
                local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(characterInfo.realm) or characterInfo.realm
                inner = inner .. " - " .. displayRealm
            end
            inner = inner .. "|r"
            row.badgeText:SetText(FormatParenBadge(inner))
        end
        row.badgeText:Show()
    end
    
    ApplyReputationRowProgressChrome(row, reputation, rowWidth)
    
    row:SetScript("OnEnter", function(self)
        local tooltipService = ShowTooltip or (ns and ns.UI_ShowTooltip)
        if not tooltipService then return end
        
        local success, err = pcall(function()
            local lines = {}
            
            -- Paragon info
            if reputation.hasParagon and reputation.paragon then
                table.insert(lines, {
                    left = (ns.L and ns.L["REP_PARAGON_PROGRESS"]) or "Paragon Progress:",
                    right = FormatReputationProgress(reputation.paragon.current, reputation.paragon.max),
                    leftColor = {1, 0.4, 1}, rightColor = {1, 0.4, 1}
                })
                if reputation.paragon.completedCycles and reputation.paragon.completedCycles > 0 then
                    table.insert(lines, {
                        left = (ns.L and ns.L["REP_CYCLES_COLON"]) or "Cycles:",
                        right = tostring(reputation.paragon.completedCycles),
                        leftColor = {1, 0.4, 1}, rightColor = {1, 0.4, 1}
                    })
                end
                if reputation.paragon.hasRewardPending then
                    table.insert(lines, {text = "|cff00ff00" .. ((ns.L and ns.L["REP_REWARD_AVAILABLE"]) or "Reward Available!") .. "|r", color = {1, 1, 1}})
                end
            end
            
            -- Character progress (from aggregated data)
            local allCharData = (characterInfo and characterInfo.allCharData) or {}
            AppendReputationCharacterProgressLines(lines, allCharData)
            
            tooltipService(self, {
                type = "custom",
                icon = reputation.iconTexture,
                title = reputation.name or ((ns.L and ns.L["TAB_REPUTATION"]) or "Reputation"),
                description = (reputation.description and reputation.description ~= "") and reputation.description or nil,
                lines = lines,
            })
        end)
        
        if not success then
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                local errMsg = "(error)"
                if type(err) == "string" and err ~= "" and not (issecretvalue and issecretvalue(err)) then
                    errMsg = err
                end
                DebugPrint("|cffff0000[RepUI Tooltip Error]|r " .. errMsg)
            end
        end
    end)
    
    row:SetScript("OnLeave", function(self)
        if HideTooltip then
            HideTooltip()
        end
    end)
    
    return yOffset + REP_ROW_HEIGHT + REP_ROW_GAP, isExpanded
end

-- Stable reputation row scripts (no per-paint closures). PopulateReputationRow stores the painted
-- reputation / character info and the subfaction collapse state on the row (row._wnRep*); these read
-- them at hover / click time (2026-10-22).
local function RepRowSubfactionToggle(self)
    local row = self._wnRepRow or self
    local collapseKey, ToggleExpand = row._wnRepCollapseKey, row._wnRepToggleExpand
    if not collapseKey or not ToggleExpand then return end
    row._wnRepExpanded = not row._wnRepExpanded
    ns.UI_CollapseExpandSetState(row.collapseBtn, row._wnRepExpanded)
    ToggleExpand(collapseKey, row._wnRepExpanded)
end

local function RepRowShowTooltip(self, tooltipService, reputation, characterInfo)
    local lines = {}

    if reputation.hasParagon and reputation.paragon then
        table.insert(lines, {
            left = (ns.L and ns.L["REP_PARAGON_PROGRESS"]) or "Paragon Progress:",
            right = FormatReputationProgress(reputation.paragon.current, reputation.paragon.max),
            leftColor = {1, 0.4, 1}, rightColor = {1, 0.4, 1}
        })
        if reputation.paragon.completedCycles and reputation.paragon.completedCycles > 0 then
            table.insert(lines, {
                left = (ns.L and ns.L["REP_CYCLES_COLON"]) or "Cycles:",
                right = tostring(reputation.paragon.completedCycles),
                leftColor = {1, 0.4, 1}, rightColor = {1, 0.4, 1}
            })
        end
        if reputation.paragon.hasRewardPending then
            table.insert(lines, {text = "|cff00ff00" .. ((ns.L and ns.L["REP_REWARD_AVAILABLE"]) or "Reward Available!") .. "|r", color = {1, 1, 1}})
        end
    end

    local allCharData = (characterInfo and characterInfo.allCharData) or {}
    AppendReputationCharacterProgressLines(lines, allCharData)

    tooltipService(self, {
        type = "custom",
        icon = reputation.iconTexture,
        title = reputation.name or ((ns.L and ns.L["TAB_REPUTATION"]) or "Reputation"),
        description = (reputation.description and reputation.description ~= "") and reputation.description or nil,
        lines = lines,
    })
end

local function RepRowOnEnter(self)
    local tooltipService = ShowTooltip or (ns and ns.UI_ShowTooltip)
    if not tooltipService then return end
    local reputation = self._wnRepData
    if not reputation then return end

    local success, err = pcall(RepRowShowTooltip, self, tooltipService, reputation, self._wnRepCharInfo)

    if not success then
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            local errMsg = "(error)"
            if type(err) == "string" and err ~= "" and not (issecretvalue and issecretvalue(err)) then
                errMsg = err
            end
            DebugPrint("|cffff0000[RepUI Tooltip Error]|r " .. errMsg)
        end
    end
end

local function RepRowOnLeave(self)
    if HideTooltip then
        HideTooltip()
    end
end

---Populate a reputation row frame with data (for virtual list reuse)
---@param row Frame Pooled reputation row frame
---@param entry table Flat list entry with .data (reputation), .factionID, .rowIdx, .rowWidth, .subfactions, .characterInfo, .IsExpanded, .ToggleExpand, .isSubfaction
local function PopulateReputationRow(row, entry)
    local reputation = entry.data
    local factionID = entry.factionID
    local rowIndex = entry.rowIdx
    local rowWidth = entry.rowWidth or 800
    local subfactions = entry.subfactions
    local characterInfo = entry.characterInfo
    local IsExpanded = entry.IsExpanded
    local ToggleExpand = entry.ToggleExpand

    -- Alternating background
    ns.UI.Factory:ApplyRowBackground(row, rowIndex)

    local isExpanded = false
    local hasSubfactions = subfactions and #subfactions > 0

    if hasSubfactions then
        local collapseKey = "rep-subfactions-" .. factionID
        isExpanded = IsExpanded(collapseKey, false)

        if not row.collapseBtn then
            row.collapseBtn = ns.UI_CreateCollapseExpandControl(row, isExpanded, { enableMouse = true })
        end

        row.collapseBtn:ClearAllPoints()
        row.collapseBtn:SetPoint("LEFT", row, "LEFT", REP_ROW.offsets[1], 0)
        ns.UI_CollapseExpandSetState(row.collapseBtn, isExpanded)

        row._wnRepCollapseKey = collapseKey
        row._wnRepToggleExpand = ToggleExpand
        row._wnRepExpanded = isExpanded
        row.collapseBtn._wnRepRow = row
        row.collapseBtn:SetScript("OnClick", RepRowSubfactionToggle)
        row:SetScript("OnClick", RepRowSubfactionToggle)
        row.collapseBtn:SetFrameLevel((row:GetFrameLevel() or 0) + 25)
        row.collapseBtn:Show()
    else
        if row.collapseBtn then row.collapseBtn:Hide() end
        -- Pooled row: drop the previous faction's toggle, or clicking this row collapsed / expanded
        -- the sub-factions of whatever faction the row showed before (2026-10-22).
        if row._wnRepCollapseKey then
            row._wnRepCollapseKey = nil
            row._wnRepToggleExpand = nil
            row:SetScript("OnClick", nil)
        end
    end

    local standingWord = ""
    local standingNumber = ""
    local standingColorCode = ""

    local textStartOffset = (hasSubfactions and REP_ROW.offsets[2] or REP_ROW.offsets[1]) + REP_ROW.pad

    if reputation.friendship and reputation.friendship.reactionText then
        standingWord = reputation.friendship.reactionText
        standingColorCode = SemanticGoldHex()
    elseif reputation.renown and reputation.renown.level and reputation.renown.level > 0 then
        standingWord = (ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown"
        standingNumber = tostring(reputation.renown.level)
        standingColorCode = SemanticGoldHex()
    elseif reputation.friendship and reputation.friendship.level and reputation.friendship.level > 0 then
        standingWord = LEVEL or "Level"
        standingNumber = tostring(reputation.friendship.level)
        standingColorCode = SemanticGoldHex()
    elseif reputation.standing and reputation.standing.name then
        standingWord = reputation.standing.name
        local c = reputation.standing.color
        if c then
            standingColorCode = format("|cff%02x%02x%02x", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255)
        else
            standingColorCode = ThemeTextHex("Bright")
        end
    else
        standingWord = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
        standingColorCode = SemanticColorHex(COLORS.red)
    end

    if standingWord ~= "" then
        if not row.standingText then
            row.standingText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.standingText:SetJustifyH("LEFT")
            row.standingText:SetWidth(REP_ROW.standingTextW)
        end
        row.standingText:ClearAllPoints()
        row.standingText:SetPoint("LEFT", textStartOffset, 0)
        local fullStandingText = standingWord
        if standingNumber ~= "" then
            fullStandingText = standingWord .. " " .. standingNumber
        end
        row.standingText:SetText(standingColorCode .. fullStandingText .. "|r")
        row.standingText:Show()

        if not row.separator then
            row.separator = FontManager:CreateFontString(row, "body", "OVERLAY")
        end
        row.separator:ClearAllPoints()
        row.separator:SetPoint("LEFT", row.standingText, "RIGHT", REP_ROW.pad, 0)
        row.separator:SetText(ThemeTextHex("Dim") .. "-|r")
        row.separator:Show()

        if not row.nameText then
            row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)
            row.nameText:SetNonSpaceWrap(false)
            row.nameText:SetMaxLines(1)
        end
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", row.separator, "RIGHT", REP_ROW.pad, 0)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -(characterInfo and REP_ROW.nameRightBadge or REP_ROW.nameRightNoBadge), 0)
        row.nameText:SetText(reputation.name or ((ns.L and ns.L["REP_UNKNOWN_FACTION"]) or "Unknown Faction"))
        ns.UI_SetTextColorRole(row.nameText, "Bright")
        row.nameText:Show()
    else
        if row.standingText then row.standingText:Hide() end
        if row.separator then row.separator:Hide() end

        if not row.nameText then
            row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)
            row.nameText:SetNonSpaceWrap(false)
            row.nameText:SetMaxLines(1)
        end
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", textStartOffset, 0)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -(characterInfo and REP_ROW.nameRightBadge or REP_ROW.nameRightNoBadge), 0)
        row.nameText:SetText(reputation.name or ((ns.L and ns.L["REP_UNKNOWN_FACTION"]) or "Unknown Faction"))
        ns.UI_SetTextColorRole(row.nameText, "Bright")
        row.nameText:Show()
    end

    if characterInfo then
        if not row.badgeText then
            row.badgeText = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.badgeText:SetJustifyH("LEFT")
            row.badgeText:SetWidth(REP_ROW.badgeTextW)
        end
        row.badgeText:ClearAllPoints()
        row.badgeText:SetPoint("LEFT", row, "RIGHT", -REP_ROW.badgeLeftFromRight, 0)

        if characterInfo.isAccountWide and not characterInfo.repProgressSplit then
            local label = ((ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account-Wide")
            row.badgeText:SetText(FormatParenBadge(SemanticColorHex(COLORS.green) .. label .. "|r"))
        elseif characterInfo.name then
            local classColor = RAID_CLASS_COLORS[characterInfo.class] or {r=1, g=1, b=1}
            local classHex = format("%02x%02x%02x", classColor.r*255, classColor.g*255, classColor.b*255)
            local inner = "|cff" .. classHex .. characterInfo.name
            if characterInfo.realm and characterInfo.realm ~= "" then
                local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(characterInfo.realm) or characterInfo.realm
                inner = inner .. " - " .. displayRealm
            end
            inner = inner .. "|r"
            row.badgeText:SetText(FormatParenBadge(inner))
        end
        row.badgeText:Show()
    else
        if row.badgeText then row.badgeText:Hide() end
    end

    ApplyReputationRowProgressChrome(row, reputation, rowWidth)

    -- Stable shared scripts read the painted reputation from the row (2026-10-22: were 2 closures per paint).
    row._wnRepData = reputation
    row._wnRepCharInfo = characterInfo
    row:SetScript("OnEnter", RepRowOnEnter)
    row:SetScript("OnLeave", RepRowOnLeave)
end

-- ROW PATCH (2026-10-22): a value-only WN_REPUTATION_UPDATED re-aggregates just the changed factions
-- and repaints their rows in place instead of rebuilding the whole list. The last full paint records
-- its VLM bodies + flat lists here; a list rebuilt since (or any doubt) falls back to the full redraw.
local repPaint = { container = nil, searchActive = false, bodies = {}, flatLists = {} }
local repPatchFound = {}

local function ForgetReputationPaint()
    repPaint.container = nil
    repPaint.searchActive = false
    local bodies, flatLists = repPaint.bodies, repPaint.flatLists
    for i = #bodies, 1, -1 do
        bodies[i] = nil
        flatLists[i] = nil
    end
end

---The painted list for `container` is still the one recorded by the last DrawReputationList.
local function HasReputationPaint(container)
    if not container or repPaint.container ~= container then return false end
    if container.IsShown and not container:IsShown() then return false end
    local bodies, flatLists = repPaint.bodies, repPaint.flatLists
    for i = 1, #bodies do
        if bodies[i]._vlm_flatList ~= flatLists[i] then return false end
    end
    return true
end

---Tracked characters (the roster the Reputation list aggregates over).
local function CollectTrackedCharacters()
    local allCharacters = WarbandNexus:GetAllCharacters()
    local characters = {}
    if allCharacters then
        for ai = 1, #allCharacters do
            local char = allCharacters[ai]
            if char.isTracked ~= false then  -- Only tracked characters
                table.insert(characters, char)
            end
        end
    end
    return characters
end

local function PatchEntryFactionID(pe)
    return pe.factionID or (pe.data and pe.data.factionID)
end

---Re-aggregate the changed factions and repaint their rows. Every changed faction must still sit in
---the painted list (a collapsed sub-faction counts: nothing of it is painted) with the same scope.
---@param container Frame resultsContainer
---@param changedFactionIDs table [factionID] = true
---@return boolean patched false = caller redraws in full
local function TryPatchReputationRows(container, changedFactionIDs)
    if type(changedFactionIDs) ~= "table" or repPaint.searchActive or not HasReputationPaint(container) then
        return false
    end
    if ns.ReputationLoadingState and ns.ReputationLoadingState.isLoading then return false end
    local query = SearchStateManager and SearchStateManager:GetQuery("reputation")
    if query and ((issecretvalue and issecretvalue(query)) or query ~= "") then return false end
    if next(changedFactionIDs) == nil then return true end   -- the scan changed no stored row
    if not WarbandNexus.GetReputationsForFactions then return false end

    local fresh = WarbandNexus:GetReputationsForFactions(changedFactionIDs)
    local factionMap = BuildReputationFactionMap(fresh or {}, CollectTrackedCharacters(), changedFactionIDs)
    local bodies, flatLists = repPaint.bodies, repPaint.flatLists
    for k in pairs(repPatchFound) do repPatchFound[k] = nil end

    -- Pass 1: verify (no partial patch).
    for bi = 1, #bodies do
        local fl = flatLists[bi]
        for i = 1, #fl do
            local pe = fl[i].type == "row" and fl[i].populateEntry
            if pe then
                local fid = PatchEntryFactionID(pe)
                if fid and changedFactionIDs[fid] then
                    local fm = factionMap[fid]
                    local ci = pe.characterInfo
                    if not fm or (fm.isAccountWide == true) ~= (ci and ci.isAccountWide == true) then
                        return false
                    end
                    repPatchFound[fid] = true
                end
                local subs = pe.subfactions
                if subs then
                    for si = 1, #subs do
                        local sid = subs[si].data and subs[si].data.factionID
                        if sid and changedFactionIDs[sid] then repPatchFound[sid] = true end
                    end
                end
            end
        end
    end
    for fid in pairs(changedFactionIDs) do
        if not repPatchFound[fid] then return false end
    end

    -- Pass 2: swap the fresh aggregate into the flat-list entries (off-screen rows read them on scroll;
    -- this VLM repopulates every row it paints -- no incrementalRowReuse).
    for bi = 1, #bodies do
        local fl = flatLists[bi]
        for i = 1, #fl do
            local pe = fl[i].type == "row" and fl[i].populateEntry
            local fid = pe and PatchEntryFactionID(pe)
            local fm = fid and changedFactionIDs[fid] and factionMap[fid]
            if fm then
                pe.data = fm.data
                local ci = pe.characterInfo
                if ci then
                    ci.name = fm.characterName
                    ci.class = fm.characterClass
                    ci.level = fm.characterLevel
                    ci.realm = fm.characterRealm
                    ci.allCharData = fm.allCharData or {}
                    ci.sessionReputation = fm.sessionReputation
                    ci.bestReputation = fm.bestReputation or fm.data
                    ci.repProgressSplit = fm.repProgressSplit
                end
            end
        end
    end
    -- The aggregate snapshot no longer matches the DB: the next full draw (expand / search) rebuilds it.
    InvalidateRepDrawCaches()

    -- Repaint the changed rows that are on screen.
    for bi = 1, #bodies do
        local fl = flatLists[bi]
        local vis = bodies[bi]._virtualVisibleFrames
        if vis then
            for j = 1, #vis do
                local v = vis[j]
                local it = v and not v.isHeader and v.index and fl[v.index]
                local pe = it and it.populateEntry
                local fid = pe and PatchEntryFactionID(pe)
                if fid and changedFactionIDs[fid] and v.frame then
                    local ok, err = pcall(PopulateReputationRow, v.frame, pe)
                    if not ok and IsDebugModeEnabled and IsDebugModeEnabled() then
                        DebugPrint("|cffff0000[RepUI patch]|r " .. tostring(err))
                    end
                end
            end
        end
    end
    return true
end

-- MAIN DRAW FUNCTION

function WarbandNexus:DrawReputationList(container, width)
    if not container then return 0 end
    ForgetReputationPaint()
    
    -- Hide empty state container (will be shown again if needed)
    HideEmptyStateCard(container, "reputation")

    local mfForVirtual = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfForVirtual and ns.VirtualListModule and ns.VirtualListModule.ClearVirtualScroll then
        ns.VirtualListModule.ClearVirtualScroll(mfForVirtual)
    end
    
    -- PERFORMANCE: Release pooled frames back to pool (prevents frame leaks)
    if ReleaseAllPooledChildren then
        ReleaseAllPooledChildren(container)
    end
    
    -- Clean up old non-virtual children (headers, notice frames, empty-state text)
    -- from previous render. VLM handles its own _isVirtualRow frames.
    local oldChildren = {container:GetChildren()}
    for i = 1, #oldChildren do
        ReleaseReputationRowsFromSubtree(oldChildren[i])
    end
    -- Section wraps / bodies / headers are pooled per container (SectionPool) and re-bound below by
    -- section key; each rep update used to park ~3 new frames per section in the recycle bin forever
    -- (2026-10-22). Anything else non-virtual is real garbage.
    local SP = ns.UI_SectionPool
    SP.BeginPass(container)
    for i = 1, #oldChildren do
        local child = oldChildren[i]
        if not child._isVirtualRow and not child._wnSectionPooled then
            SP.Discard(child)
        end
    end
    local oldRegions = {container:GetRegions()}
    for i = 1, #oldRegions do
        local region = oldRegions[i]
        if region:GetObjectType() == "FontString" then
            region:Hide()
        end
    end
    
    local parent = container
    local yOffset = 0
    local repChainTail = nil
    local COLLAPSE_H_REP = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36
    
    
    -- Check if C_Reputation API is available (for modern WoW)
    if not C_Reputation or not C_Reputation.GetNumFactions then
        local errorFrame = CreateNoticeFrame(
            parent,
            (ns.L and ns.L["REP_API_UNAVAILABLE_TITLE"]) or "Reputation API Not Available",
            (ns.L and ns.L["REP_API_UNAVAILABLE_DESC"]) or "The C_Reputation API is not available on this server. This feature requires WoW 12.0.5 (Midnight).",
            "alert",
            width - 20,
            100
        )
        -- Parent is the already-inset results container: fill it (no second side inset).
        errorFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
        errorFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
        
        return yOffset + GetLayout().emptyStateSpacing + BASE_INDENT
    end
    
    -- Get search text from SearchStateManager
    local reputationSearchText = SearchStateManager:GetQuery("reputation")
    
    -- Get all characters (filter tracked only)
    local characters = CollectTrackedCharacters()
    
    if not characters or #characters == 0 then
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, "", "reputation")
        SearchStateManager:UpdateResults("reputation", 0)
        return height
    end
    
    -- Get faction metadata
    local factionMetadata = self.db.global.factionMetadata or {}
    
    -- Expanded state
    local expanded = self.db.profile.reputationExpanded or {}
    
    -- Helper functions for expand/collapse
    local function IsExpanded(key, default)
        if self.db.profile.reputationExpandOverride == "all_collapsed" then
            return false
        end
        if expanded[key] == nil then
            return default or false
        end
        return expanded[key]
    end
    
    local function PersistExpand(key, isExpanded)
        if self.db.profile.reputationExpandOverride then
            self.db.profile.reputationExpandOverride = nil
        end
        if not self.db.profile.reputationExpanded then
            self.db.profile.reputationExpanded = {}
        end
        self.db.profile.reputationExpanded[key] = isExpanded
    end

    local function ToggleExpand(key, isExpanded)
        PersistExpand(key, isExpanded)
        WarbandNexus:RedrawReputationResultsOnly(true)
    end
    
    
    local aggregatedHeaders, accountWideHeaders, characterBasedHeaders =
        GetReputationAggregateSnapshot(characters, factionMetadata)
    
    if not aggregatedHeaders or #aggregatedHeaders == 0 then
        -- Show reputation-specific empty state (parent = already-inset results container -> fillParent at 0)
        local yOffset = 0
        
        -- Check if this is a search result or general "no data" state
        if reputationSearchText and reputationSearchText ~= "" then
            -- Search-related empty state: use SearchResultsRenderer
            local height = SearchResultsRenderer:RenderEmptyState(self, parent, reputationSearchText, "reputation")
            SearchStateManager:UpdateResults("reputation", 0)
            return height
        else
            if ns.UI_ShowTabEmptyStateCard then
                local height = ns.UI_ShowTabEmptyStateCard(parent, "reputation", yOffset, { fillParent = true })
                SearchStateManager:UpdateResults("reputation", 0)
                return height
            end
            local _, height = CreateEmptyStateCard(parent, "reputation", yOffset, { fillParent = true })
            SearchStateManager:UpdateResults("reputation", 0)
            return yOffset + height
        end
    end
    
    local function GetHeaderIcon(headerName)
        if not headerName or headerName == "" then
            return "Interface\\Icons\\Achievement_Reputation_01"
        end
        if issecretvalue and issecretvalue(headerName) then
            return "Interface\\Icons\\Achievement_Reputation_01"
        end
        if headerName:find("Guild") then
            return "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
        elseif headerName:find("Midnight") or headerName:find("Quel'Thalas") or headerName:find("Coiled Isle") or headerName:find("Ula'tek") then
            return "Interface\\Icons\\Spell_Shadow_Teleport"
        elseif headerName:find("Alliance") then
            return "Interface\\Icons\\Achievement_PVP_A_A"
        elseif headerName:find("Horde") then
            return "Interface\\Icons\\Achievement_PVP_H_H"
        elseif headerName:find("War Within") or headerName:find("Khaz Algar") then
            return "Interface\\Icons\\INV_Misc_Gem_Diamond_01"
        elseif headerName:find("Dragonflight") or headerName:find("Dragon") then
            return "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"
        elseif headerName:find("Shadowlands") then
            return "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
        elseif headerName:find("Battle") or headerName:find("Azeroth") then
            return "Interface\\Icons\\INV_Sword_39"
        elseif headerName:find("Legion") then
            return "Interface\\Icons\\Spell_Shadow_Twilight"
        elseif headerName:find("Draenor") then
            return "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc"
        elseif headerName:find("Pandaria") then
            return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
        elseif headerName:find("Cataclysm") then
            return "Interface\\Icons\\Spell_Fire_Flameshock"
        elseif headerName:find("Lich King") or headerName:find("Northrend") then
            return "Interface\\Icons\\Spell_Shadow_SoulLeech_3"
        elseif headerName:find("Burning Crusade") or headerName:find("Outland") then
            return "Interface\\Icons\\Spell_Fire_FelFlameStrike"
        elseif headerName:find("Classic") then
            return "Interface\\Icons\\INV_Misc_Book_11"
        else
            return "Interface\\Icons\\Achievement_Reputation_01"
        end
    end
    
    -- Account-wide vs character-based sections (pre-split in aggregate snapshot cache)
    -- Count total factions (TOP-LEVEL only — excludes children/subfactions)
    local totalAccountWide = 0
    for hi = 1, #accountWideHeaders do
        local h = accountWideHeaders[hi]
        local hf = h.factions
        for fi = 1, #hf do
            local faction = hf[fi]
            if faction and faction.data and not faction.data.parentFactionID then
                totalAccountWide = totalAccountWide + 1
            end
        end
    end
    
    local totalCharacterBased = 0
    for hi = 1, #characterBasedHeaders do
        local h = characterBasedHeaders[hi]
        local hf = h.factions
        for fi = 1, #hf do
            local faction = hf[fi]
            if faction and faction.data and not faction.data.parentFactionID then
                totalCharacterBased = totalCharacterBased + 1
            end
        end
    end
    
    local Factory = ns.UI.Factory
    local rowGap = REP_ROW_GAP
    local globalRowIdx = 0

    local function MeasureChildrenHeight(frame)
        if not frame then return 0.1 end
        local top = frame:GetTop()
        if not top then
            return math.max(0.1, frame._wnSectionFullH or frame:GetHeight() or 0.1)
        end
        local lowest = top
        local children = {frame:GetChildren()}
        for i = 1, #children do
            local child = children[i]
            if child and child:IsShown() then
                local bottom = child:GetBottom()
                if bottom and bottom < lowest then
                    lowest = bottom
                end
            end
        end
        return math.max(0.1, top - lowest)
    end

    local function SyncScrollMetrics()
        local totalH = MeasureChildrenHeight(parent)
        parent:SetHeight(math.max(1, totalH))
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        local scrollChild = parent and parent:GetParent()
        if not (mf and scrollChild and mf.scroll and scrollChild == mf.scrollChild) then
            return
        end
        local targetTabBodyH = 8 + totalH
        local targetScrollChildH = math.max(targetTabBodyH + 8, mf.scroll:GetHeight())
        scrollChild:SetHeight(targetScrollChildH)
        if Factory and Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(mf.scroll)
        end
        if Factory and Factory.UpdateHorizontalScrollBarVisibility then
            Factory:UpdateHorizontalScrollBarVisibility(mf.scroll)
        end
        if mf._virtualScrollUpdate then
            mf._virtualScrollUpdate()
        end
    end

    local function CreateWrap(parentFrame, wrapWidth, poolKey)
        local wrap = SP.Acquire(container, "rep:wrap:" .. poolKey, parentFrame, math.max(1, wrapWidth), COLLAPSE_H_REP + 0.1)
        if not wrap then return nil end
        wrap:SetWidth(math.max(1, wrapWidth))
        wrap:SetHeight(COLLAPSE_H_REP + 0.1)
        if wrap.SetClipsChildren then
            wrap:SetClipsChildren(true)
        end
        return wrap
    end

    local function CreateBody(wrap, bodyWidth, poolKey)
        local body = SP.Acquire(container, "rep:body:" .. poolKey, wrap, math.max(1, bodyWidth), 0.1)
        if not body then return nil end
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, -COLLAPSE_H_REP)
        body:SetPoint("TOPRIGHT", wrap, "TOPRIGHT", 0, -COLLAPSE_H_REP)
        body:SetWidth(math.max(1, bodyWidth))
        body:SetHeight(0.1)
        if body.SetClipsChildren then
            body:SetClipsChildren(true)
        end
        body:Hide()
        return body
    end

    local function FinalizeBodyHeight(body)
        if not body then return 0.1 end
        if body._wnVirtualContentHeight then
            local fullH = body._wnVirtualContentHeight
            body._wnSectionFullH = fullH
            return fullH
        end
        local fullH = MeasureChildrenHeight(body)
        body._wnSectionFullH = fullH
        return fullH
    end

    local function ChainTopFrame(frame, gap)
        if not frame then return end
        ChainSectionFrameBelow(parent, frame, repChainTail, 0, gap, repChainTail and nil or 0)
        repChainTail = frame
    end

    local function BuildFilteredList(headerData, scopeTag)
        local rawSearch = reputationSearchText or ""
        local isSecret = rawSearch and issecretvalue and issecretvalue(rawSearch)
        local searchTextKey = isSecret and "" or rawSearch
        local isSearching = not isSecret and rawSearch ~= ""

        local factionList = {}
        local bff = headerData.factions or {}
        for fi = 1, #bff do
            local faction = bff[fi]
            if faction and faction.data and not faction.data.parentFactionID then
                tinsert(factionList, {
                    faction = faction,
                    subfactions = faction.subfactions,
                    originalIndex = faction.factionID,
                })
            end
        end

        if not isSearching then
            return factionList, factionList, false
        end

        local cacheKey = (headerData.name or "") .. "|" .. scopeTag .. "|" .. searchTextKey
        local cached = cachedFilteredResults[cacheKey]
        if cached and cached.searchText == searchTextKey then
            return factionList, cached.filteredList, isSearching
        end

        local filtered = {}
        for ii = 1, #factionList do
            local item = factionList[ii]
            local itemName = SafeLower(item.faction.data.name)
            local parentMatches = not isSearching or itemName:find(reputationSearchText, 1, true)
            local filteredSubs = nil
            local hasMatchingSub = false
            if isSearching and item.subfactions and not parentMatches then
                filteredSubs = {}
                local subs = item.subfactions
                for si = 1, #subs do
                    local sub = subs[si]
                    local subName = SafeLower(sub.data.name)
                    if subName:find(reputationSearchText, 1, true) then
                        table.insert(filteredSubs, sub)
                        hasMatchingSub = true
                    end
                end
            end
            if parentMatches then
                table.insert(filtered, item)
            elseif hasMatchingSub then
                table.insert(filtered, {
                    faction = item.faction,
                    subfactions = filteredSubs,
                    originalIndex = item.originalIndex,
                    _forceExpand = true,
                })
            end
        end

        cachedFilteredResults[cacheKey] = {
            searchText = searchTextKey,
            filteredList = filtered
        }
        return factionList, filtered, isSearching
    end

    local repSearchActive = reputationSearchText and reputationSearchText ~= ""
        and not (issecretvalue and issecretvalue(reputationSearchText))
    if repSearchActive then
        totalAccountWide = 0
        for hi = 1, #accountWideHeaders do
            local _, fl = BuildFilteredList(accountWideHeaders[hi], "AW")
            totalAccountWide = totalAccountWide + #fl
        end
        totalCharacterBased = 0
        for hi = 1, #characterBasedHeaders do
            local _, fl = BuildFilteredList(characterBasedHeaders[hi], "CB")
            totalCharacterBased = totalCharacterBased + #fl
        end
        if totalAccountWide + totalCharacterBased == 0 then
            HideEmptyStateCard(parent, "reputation")
            HideEmptyStateCard(parent, ns.UI_SEARCH_EMPTY_TAB_KEY or "search")
            local height = SearchResultsRenderer:RenderEmptyState(self, parent, reputationSearchText, "reputation")
            SearchStateManager:UpdateResults("reputation", 0)
            return height
        end
    end

    local function RenderRowsIntoBody(body, bodyWidth, filteredFactionList)
        body._wnVirtualContentHeight = nil
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        local VLM = ns.VirtualListModule
        if not mf or not mf.scroll or not body or not VLM or not VLM.SetupVirtualList then
            return
        end

        local stride = REP_ROW_HEIGHT + rowGap
        local clampW = ns.UI_ClampRowPaintWidth
        local flatList = {}
        local rowY = 0
        local parentRowWidth = clampW and clampW(body, 0, bodyWidth) or bodyWidth

        for ri = 1, #filteredFactionList do
            local item = filteredFactionList[ri]
            globalRowIdx = globalRowIdx + 1
            local charInfo = {
                name = item.faction.characterName,
                class = item.faction.characterClass,
                level = item.faction.characterLevel,
                isAccountWide = item.faction.isAccountWide,
                realm = item.faction.characterRealm,
                allCharData = item.faction.allCharData or {},
                sessionReputation = item.faction.sessionReputation,
                bestReputation = item.faction.bestReputation or item.faction.data,
                repProgressSplit = item.faction.repProgressSplit,
            }
            local collapseKey = "rep-subfactions-" .. tostring(item.faction.factionID or 0)
            local subExpanded = IsExpanded(collapseKey, false)
            local subsToRender = item.subfactions
            local showSubs = subExpanded or item._forceExpand

            flatList[#flatList + 1] = {
                type = "row",
                yOffset = rowY,
                height = stride,
                rowPaintHeight = REP_ROW_HEIGHT,
                xOffset = 0,
                rowWidth = parentRowWidth,
                populateEntry = {
                    data = item.faction.data,
                    factionID = item.faction.factionID,
                    rowIdx = globalRowIdx,
                    rowWidth = parentRowWidth,
                    isSubfaction = false,
                    subfactions = subsToRender,
                    characterInfo = charInfo,
                    IsExpanded = IsExpanded,
                    ToggleExpand = ToggleExpand,
                },
            }
            rowY = rowY + stride

            if showSubs and subsToRender and #subsToRender > 0 then
                local subIndent = BASE_INDENT + SUBROW_EXTRA_INDENT
                local subRowWidth = clampW and clampW(body, subIndent, bodyWidth - subIndent) or math.max(1, bodyWidth - subIndent)
                for si = 1, #subsToRender do
                    local subFaction = subsToRender[si]
                    globalRowIdx = globalRowIdx + 1
                    flatList[#flatList + 1] = {
                        type = "row",
                        yOffset = rowY,
                        height = stride,
                        rowPaintHeight = REP_ROW_HEIGHT,
                        xOffset = subIndent,
                        rowWidth = subRowWidth,
                        populateEntry = {
                            data = subFaction.data,
                            factionID = subFaction.factionID,
                            rowIdx = globalRowIdx,
                            rowWidth = subRowWidth,
                            isSubfaction = true,
                            subfactions = nil,
                            characterInfo = {
                                name = subFaction.characterName,
                                class = subFaction.characterClass,
                                level = subFaction.characterLevel,
                                isAccountWide = subFaction.isAccountWide,
                                realm = subFaction.characterRealm,
                                allCharData = subFaction.allCharData or {},
                                sessionReputation = subFaction.sessionReputation,
                                bestReputation = subFaction.bestReputation or subFaction.data,
                                repProgressSplit = subFaction.repProgressSplit,
                            },
                            IsExpanded = IsExpanded,
                            ToggleExpand = ToggleExpand,
                        },
                    }
                    rowY = rowY + stride
                end
            end
        end

        if #flatList == 0 then
            body:SetHeight(0.1)
            return
        end

        local totalHeight = VLM.SetupVirtualList(mf, body, nil, flatList, {
            createRowFn = function(container, it, _idx)
                return AcquireReputationRow(container, it.rowWidth, REP_ROW_HEIGHT)
            end,
            populateRowFn = function(row, it, _idx)
                local ok, err = pcall(PopulateReputationRow, row, it.populateEntry)
                if not ok and IsDebugModeEnabled and IsDebugModeEnabled() then
                    DebugPrint("|cffff0000[RepUI VLM]|r populateRowFn: " .. tostring(err))
                end
            end,
            releaseRowFn = ReleaseReputationRow,
        })
        -- Row patch registry (TryPatchReputationRows).
        repPaint.bodies[#repPaint.bodies + 1] = body
        repPaint.flatLists[#repPaint.flatLists + 1] = flatList

        body._wnVirtualContentHeight = totalHeight
        body:SetHeight(math.max(0.1, totalHeight or rowY))
    end

    local function RenderSection(sectionKey, sectionTitle, iconTexture, isAtlas, headers, scopeTag)
        local sectionExpanded = IsExpanded(sectionKey, false)
        local sectionWrap = CreateWrap(parent, width, sectionKey)
        local sectionBody = sectionWrap and CreateBody(sectionWrap, width, sectionKey)
        if not (sectionWrap and sectionBody) then return end

        -- CurrencyUI parity: when a nested category section opens/closes, reflow ancestor bodies/wraps
        -- so outer section height tracks nested layout.
        local sectionCtx = { body = sectionBody, wrap = sectionWrap, parentCtx = nil }
        local function ReflowAncestors(ctx)
            if not ctx or not ctx.body or not ctx.wrap then return end
            local bodyH = FinalizeBodyHeight(ctx.body)
            if ctx.body:IsShown() then
                ctx.body:SetHeight(math.max(0.1, bodyH))
                ctx.wrap:SetHeight(COLLAPSE_H_REP + ctx.body:GetHeight())
            else
                ctx.wrap:SetHeight(COLLAPSE_H_REP + 0.1)
            end
            ReflowAncestors(ctx.parentCtx)
        end

        ChainTopFrame(sectionWrap, repChainTail and SECTION_SPACING or nil)
        local sectionHeader, _, sectionIcon = CreateCollapsibleHeader(
            sectionWrap,
            sectionTitle,
            sectionKey,
            sectionExpanded,
            function() end,
            iconTexture,
            isAtlas,
            nil,
            nil,
            SP.HeaderOpts(container, "rep:hdr:" .. sectionKey, {
                animatedContent = function() return sectionBody end,
                persistToggle = function(exp)
                    PersistExpand(sectionKey, exp)
                end,
                sectionOnUpdate = function(drawH)
                    sectionWrap:SetHeight(COLLAPSE_H_REP + math.max(0.1, drawH or 0))
                    SyncScrollMetrics()
                end,
                sectionOnComplete = function(exp)
                    if not exp then
                        sectionBody:Hide()
                        sectionBody:SetHeight(0.1)
                    end
                    sectionBody._wnSectionFullH = FinalizeBodyHeight(sectionBody)
                    sectionWrap:SetHeight(COLLAPSE_H_REP + (exp and sectionBody._wnSectionFullH or 0.1))
                    SyncScrollMetrics()
                end,
            })
        )
        SP.Remember(container, "rep:hdr:" .. sectionKey, sectionHeader)
        sectionHeader:ClearAllPoints()
        sectionHeader:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
        sectionHeader:SetPoint("TOPRIGHT", sectionWrap, "TOPRIGHT", 0, 0)
        sectionHeader:SetHeight(COLLAPSE_H_REP)
        if sectionIcon and scopeTag == "AW" then
            sectionIcon:SetTexture(nil)
            sectionIcon:SetAtlas("warbands-icon")
            sectionIcon:SetSize(27, 36)
        end

        local headerTail = nil
        local sectionHeaders = headers or {}
        for shi = 1, #sectionHeaders do
            local headerData = sectionHeaders[shi]
            if #headerData.factions > 0 then
                local factionList, filteredFactionList, isSearching = BuildFilteredList(headerData, scopeTag)
                if not isSearching or #filteredFactionList > 0 then
                    local headerKey = (scopeTag == "AW" and "filtered-header-" or "filtered-cb-header-") .. (headerData.name or "")
                    local headerExpanded = isSearching and true or IsExpanded(headerKey, false)
                    local headerWrap = CreateWrap(sectionBody, width - BASE_INDENT, headerKey)
                    local headerBody = headerWrap and CreateBody(headerWrap, width - BASE_INDENT, headerKey)
                    if headerWrap and headerBody then
                        ChainSectionFrameBelow(sectionBody, headerWrap, headerTail, BASE_INDENT, headerTail and SECTION_SPACING or nil, headerTail and nil or SECTION_SPACING)
                        headerTail = headerWrap

                        local nodeCtx = { body = headerBody, wrap = headerWrap, parentCtx = sectionCtx }
                        local filteredCount = isSearching and #filteredFactionList or #factionList
                        local header = CreateCollapsibleHeader(
                            headerWrap,
                            (headerData.name or "") .. " (" .. FormatNumber(filteredCount) .. ")",
                            headerKey,
                            headerExpanded,
                            function() end,
                            GetHeaderIcon(headerData.name),
                            nil,
                            nil,
                            nil,
                            SP.HeaderOpts(container, "rep:hdr:" .. headerKey, {
                                animatedContent = function() return headerBody end,
                                persistToggle = function(exp)
                                    PersistExpand(headerKey, exp)
                                end,
                                sectionOnUpdate = function(drawH)
                                    headerWrap:SetHeight(COLLAPSE_H_REP + math.max(0.1, drawH or 0))
                                    ReflowAncestors(nodeCtx.parentCtx)
                                end,
                                sectionOnComplete = function(exp)
                                    if not exp then
                                        headerBody:Hide()
                                        headerBody:SetHeight(0.1)
                                    end
                                    headerBody._wnSectionFullH = FinalizeBodyHeight(headerBody)
                                    headerWrap:SetHeight(COLLAPSE_H_REP + (exp and headerBody._wnSectionFullH or 0.1))
                                    ReflowAncestors(nodeCtx.parentCtx)
                                    SyncScrollMetrics()
                                end,
                            })
                        )
                        SP.Remember(container, "rep:hdr:" .. headerKey, header)
                        header:ClearAllPoints()
                        header:SetPoint("TOPLEFT", headerWrap, "TOPLEFT", 0, 0)
                        header:SetPoint("TOPRIGHT", headerWrap, "TOPRIGHT", 0, 0)
                        header:SetHeight(COLLAPSE_H_REP)

                        RenderRowsIntoBody(headerBody, width - BASE_INDENT, filteredFactionList)
                        headerBody._wnSectionFullH = FinalizeBodyHeight(headerBody)
                        if headerExpanded then
                            headerBody:Show()
                            headerBody:SetHeight(math.max(0.1, headerBody._wnSectionFullH))
                            headerWrap:SetHeight(COLLAPSE_H_REP + headerBody:GetHeight())
                        else
                            headerBody:Hide()
                            headerBody:SetHeight(0.1)
                            headerWrap:SetHeight(COLLAPSE_H_REP + 0.1)
                        end
                    end
                end
            end
        end

        sectionBody._wnSectionFullH = FinalizeBodyHeight(sectionBody)
        if sectionExpanded then
            sectionBody:Show()
            sectionBody:SetHeight(math.max(0.1, sectionBody._wnSectionFullH))
            sectionWrap:SetHeight(COLLAPSE_H_REP + sectionBody:GetHeight())
        else
            sectionBody:Hide()
            sectionBody:SetHeight(0.1)
            sectionWrap:SetHeight(COLLAPSE_H_REP + 0.1)
        end
    end

    if totalAccountWide > 0 or not repSearchActive then
        RenderSection(
            "filtered-section-accountwide",
            format((ns.L and ns.L["REP_SECTION_ACCOUNT_WIDE"]) or "Account-Wide Reputations (%s)", FormatNumber(totalAccountWide)),
            "dummy",
            nil,
            accountWideHeaders,
            "AW"
        )
    end
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
    if totalCharacterBased > 0 or not repSearchActive then
        RenderSection(
            "filtered-section-characterbased",
            format((ns.L and ns.L["REP_SECTION_CHARACTER_BASED"]) or "Character-Based Reputations (%s)", FormatNumber(totalCharacterBased)),
            GetCharacterSpecificIcon and GetCharacterSpecificIcon() or nil,
            true,
            characterBasedHeaders,
            "CB"
        )
    end

    if not repSearchActive then
        local noticeFrame = CreateNoticeFrame(
            parent,
            (ns.L and ns.L["REP_FOOTER_TITLE"]) or "Reputation Tracking",
            (ns.L and ns.L["REP_FOOTER_DESC"]) or "Reputations are scanned automatically on login and when changed. Use the in-game reputation panel to view detailed information and rewards.",
            "info",
            width - 20,
            60
        )
        ChainTopFrame(noticeFrame, PAGE_STACK.SECTION_GAP or SECTION_SPACING)
    end

    local totalReputations = 0
    local aggHdrs = aggregatedHeaders or {}
    for agi = 1, #aggHdrs do
        local headerGroup = aggHdrs[agi]
        if headerGroup and headerGroup.factions then
            totalReputations = totalReputations + #headerGroup.factions
        end
    end
    SearchStateManager:UpdateResults("reputation", totalReputations)

    SyncScrollMetrics()
    local finalHeight = MeasureChildrenHeight(parent) + (GetLayout().minBottomSpacing or 0)
    parent:SetHeight(math.max(1, finalHeight))
    repPaint.container = container
    repPaint.searchActive = repSearchActive and true or false
    return finalHeight
end

-- REPUTATION TAB WRAPPER (Fixes focus issue)

--- Reposition cached Reputation fixedHeader chrome (Collections/Items parity — WN-PERF tab revisit).
--- Same UI_PageStack_Place calls and heights as the DrawReputationTab create path (no drift on repaint).
local function RepositionReputationFixedHeader(hdrCache, headerParent, chrome, headerYOffset, contentSide, searchH)
    chrome = chrome or { headerParent = headerParent, yOffset = headerYOffset, side = contentSide }
    local titleCard = hdrCache.titleCard
    local titleH = titleCard:GetHeight()
    if not titleH or titleH <= 0 then titleH = 64 end
    headerYOffset = ns.UI_PageStack_Place(chrome, titleCard, titleH)
    titleCard:Show()
    local searchBox = hdrCache.searchBox
    if searchBox then
        headerYOffset = ns.UI_PageStack_Place(chrome, searchBox, searchH)
        searchBox:Show()
    end
    return headerYOffset
end

local function ApplyReputationResultsHeight(mainFrame, scrollChild, resultsContainer, listHeight, _animate, _fromResultsH, _fromScrollChildH)
    if not mainFrame or not scrollChild or not resultsContainer then return end
    local targetResultsH = math.max(listHeight or 1, 1)
    local CONTENT_BOTTOM_PADDING = PAGE_STACK.BOTTOM_PAD or 12
    local targetTabBodyH = (PAGE_STACK.BODY_TOP or 8) + (listHeight or 0)
    local targetScrollChildH = math.max(targetTabBodyH + CONTENT_BOTTOM_PADDING, mainFrame.scroll:GetHeight())

    local Factory = ns.UI.Factory
    resultsContainer:SetHeight(targetResultsH)
    if ns.UI_SyncMainTabScrollChrome then
        ns.UI_SyncMainTabScrollChrome(mainFrame, scrollChild, targetTabBodyH)
        return
    end
    scrollChild:SetHeight(targetScrollChildH)
    if Factory and Factory.UpdateScrollBarVisibility then
        Factory:UpdateScrollBarVisibility(mainFrame.scroll)
    end
    if Factory and Factory.UpdateHorizontalScrollBarVisibility then
        Factory:UpdateHorizontalScrollBarVisibility(mainFrame.scroll)
    end
end

function WarbandNexus:RedrawReputationResultsOnly(animateHeight)
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "reputations" then return end
    local scrollChild = mf.scrollChild
    if not scrollChild then return end
    local rc = scrollChild.resultsContainer
    if not rc or rc:GetParent() ~= scrollChild then return end
    local width = (ns.UI_ResolveResultsContainerPaintWidth and ns.UI_ResolveResultsContainerPaintWidth(mf, rc))
        or math.max(1, (scrollChild:GetWidth() or 0) - (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin() or 12) * 2)
    if width < 1 then return end

    if SearchResultsRenderer and SearchResultsRenderer.PrepareContainer then
        SearchResultsRenderer:PrepareContainer(rc)
    end

    local oldResultsH = rc:GetHeight() or 1
    local oldScrollChildH = scrollChild:GetHeight() or mf.scroll:GetHeight()
    local listHeight = self:DrawReputationList(rc, width)
    ApplyReputationResultsHeight(mf, scrollChild, rc, listHeight, animateHeight == true, oldResultsH, oldScrollChildH)

    local sc = mf.scroll
    if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
        local maxV = sc:GetVerticalScrollRange() or 0
        local cur = sc:GetVerticalScroll() or 0
        if cur > maxV then
            sc:SetVerticalScroll(maxV)
        end
    end
end

---Data-only refresh: reuse chrome when resultsContainer exists (CurrencyUI parity).
---@param parent Frame scrollChild
---@param animateResults boolean|nil
local function RefreshReputationTabData(parent, animateResults)
    if not parent then return end
    InvalidateRepDrawCaches()
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local fh = mf and mf.fixedHeader
    local fhHeight = (fh and fh:GetHeight()) or 0
    if parent.resultsContainer and fhHeight >= 100 then
        if SearchResultsRenderer and SearchResultsRenderer.PrepareContainer then
            SearchResultsRenderer:PrepareContainer(parent.resultsContainer)
        end
        WarbandNexus:RedrawReputationResultsOnly(animateResults == true)
    else
        WarbandNexus:DrawReputationTab(parent)
    end
end

function WarbandNexus:DrawReputationTab(parent)
    if not parent then
        self:Print("|cffff0000ERROR: No parent container provided to DrawReputationTab|r")
        return
    end
    
    -- Register event listener for reputation updates (only once per parent)
    if not parent.reputationUpdateHandler then
        parent.reputationUpdateHandler = true

        local function IsReputationTabActive()
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            return mf and mf:IsShown() and mf.currentTab == "reputations"
        end

        -- REPUTATION_CACHE_READY + REPUTATION_UPDATED are sent back-to-back by ReputationCacheService;
        -- coalesce the burst into one next-frame data refresh instead of two synchronous redraws.
        -- The burst repaints only the changed rows when every UPDATED in it carried a value-only payload
        -- ({ changedFactionIDs, structural = false }); anything else redraws in full (2026-10-22).
        local repRefreshPending = false
        local repBurstSawUpdate, repBurstFull = false, false
        local repBurstChanged = {}
        local function ScheduleCoalescedReputationRefresh(payload, isUpdate)
            if isUpdate then
                repBurstSawUpdate = true
                local changed = type(payload) == "table" and payload.structural == false and payload.changedFactionIDs
                if type(changed) == "table" then
                    for fid in pairs(changed) do repBurstChanged[fid] = true end
                else
                    repBurstFull = true
                end
            end
            if repRefreshPending then return end
            repRefreshPending = true
            C_Timer.After(0, function()
                repRefreshPending = false
                local patchable = repBurstSawUpdate and not repBurstFull
                repBurstSawUpdate, repBurstFull = false, false
                if parent and IsReputationTabActive() then
                    if not (patchable and TryPatchReputationRows(parent.resultsContainer, repBurstChanged)) then
                        RefreshReputationTabData(parent, false)
                    end
                else
                    -- Missed while off the tab: the next refresh must not patch on top of it.
                    ForgetReputationPaint()
                end
                for k in pairs(repBurstChanged) do repBurstChanged[k] = nil end
            end)
        end
        
        -- Loading started - only refresh if Reputations tab is active (not parent:IsVisible â€” shared scroll child)
        WarbandNexus.RegisterMessage(ReputationUIEvents, E.REPUTATION_LOADING_STARTED, function()
            InvalidateRepDrawCaches()
            if parent and IsReputationTabActive() then
                -- Background rescan under a painted list: keep the rows up; the scan's WN_REPUTATION_UPDATED
                -- patches or redraws them (was a loading-card repaint per rep gain, 2026-10-22).
                if HasReputationPaint(parent.resultsContainer) then return end
                self:DrawReputationTab(parent)
            end
        end)
        
        -- v2.0.0: Cache cleared - loading UI only when tab active
        WarbandNexus.RegisterMessage(ReputationUIEvents, E.REPUTATION_CACHE_CLEARED, function()
            InvalidateRepDrawCaches()
            ForgetReputationPaint()
            if IsReputationTabActive() then
                if parent._loadingPanel then
                    parent._loadingPanel:ShowLoading(
                        (ns.L and ns.L["REP_CLEARING_CACHE"]) or "Clearing cache and reloading...",
                        0, ""
                    )
                end
                
                -- Hide all content frames
                local children = {parent:GetChildren()}
                for _, child in pairs(children) do
                    if child ~= parent.dbVersionBadge 
                       and child ~= parent.emptyStateContainer 
                       and child ~= parent._loadingPanel then
                        child:Hide()
                    end
                end
            end
        end)
        
        -- v2.0.0: Cache ready (hide loading, show content) - results-only when chrome exists
        WarbandNexus.RegisterMessage(ReputationUIEvents, E.REPUTATION_CACHE_READY, function()
            if parent._loadingPanel then
                parent._loadingPanel:HideLoading()
            end
            
            ScheduleCoalescedReputationRefresh()
        end)
        
        -- Real-time update event (payload: { changedFactionIDs, structural } from ReputationCacheService)
        WarbandNexus.RegisterMessage(ReputationUIEvents, Constants.EVENTS.REPUTATION_UPDATED, function(_, payload)
            ScheduleCoalescedReputationRefresh(payload, true)
        end)
    end
    -- Any tab draw (loading card or a list repaint) replaces what the patch registry points at.
    ForgetReputationPaint()
    
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "ReputationCache [Loading...]"
        if self.db.global.reputationCache and next(self.db.global.reputationCache.factions or {}) then
            local cacheVersion = self.db.global.reputationCache.version or "unknown"
            dataSource = "ReputationCache v" .. cacheVersion
        end
        parent.dbVersionBadge = CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Persistent loading overlay (standard panel from SharedWidgets)
    if not parent._loadingPanel then
        local UI_CreateLoadingStatePanel = ns.UI_CreateLoadingStatePanel
        if UI_CreateLoadingStatePanel then
            parent._loadingPanel = UI_CreateLoadingStatePanel(parent)
        end
    end
    
    -- Hide empty state container (will be shown again if needed)
    HideEmptyStateCard(parent, "reputation")

    -- Fast path: cache still loading â€” skip expensive scroll-child purge + full header rebuild every tick.
    if ns.ReputationLoadingState and ns.ReputationLoadingState.isLoading then
        local mfEarly = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        local metricsEarly = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mfEarly)
        local scrollTopY = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
        local titleH = (metricsEarly and metricsEarly.titleCardHeight) or 64
        local blockGap = PAGE_STACK.BLOCK_GAP or 8
        local topM = (metricsEarly and metricsEarly.topMargin) or 0
        local searchH = PAGE_STACK.SEARCH_HEIGHT or 32
        local headerH = topM + titleH + blockGap + searchH + blockGap
        local fixedHeaderEarly = mfEarly and mfEarly.fixedHeader
        if ns.UI_CommitTabFixedHeader then
            ns.UI_CommitTabFixedHeader(mfEarly, headerH)
        elseif fixedHeaderEarly then
            fixedHeaderEarly:SetHeight(headerH)
        end
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            return UI_CreateLoadingStateCard(parent, scrollTopY, ns.ReputationLoadingState, (ns.L and ns.L["REP_LOADING_TITLE"]) or "Loading Reputation Data")
        end
        return 120
    end

    -- Clear stale scroll body on full redraw; PopulateContent already released pooled rows.
    if not parent._preparedByPopulate then
    local children = {parent:GetChildren()}
    for _, child in pairs(children) do
        -- Keep only persistent UI elements (badge, title card, loading panel)
        if child ~= parent.dbVersionBadge 
           and child ~= parent.emptyStateContainer 
           and child ~= parent._loadingPanel
           and child ~= (WarbandNexus.UI and WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame._wnReputationTitleCard)
           and child ~= (WarbandNexus.UI and WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame._wnReputationFixedHeaderCache
               and WarbandNexus.UI.mainFrame._wnReputationFixedHeaderCache.titleCard)
           and child ~= (WarbandNexus.UI and WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame._wnReputationFixedHeaderCache
               and WarbandNexus.UI.mainFrame._wnReputationFixedHeaderCache.searchBox) then
            pcall(function()
                child:Hide()
                child:ClearAllPoints()
            end)
        end
    end
    
    -- Also clear FontStrings (they're not children, they're regions)
    local regions = {parent:GetRegions()}
    for _, region in pairs(regions) do
        if region:GetObjectType() == "FontString" then
            pcall(function()
                region:Hide()
                region:ClearAllPoints()
            end)
        end
    end
    end
    
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local contentWidth = (metrics and metrics.contentWidth)
        or (ns.UI_ResolveMainTabContentWidth and ns.UI_ResolveMainTabContentWidth(mf, parent))
        or (parent:GetWidth() or 600)
    local bodyWidth = (metrics and metrics.bodyWidth)
        or (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent))
        or math.max(200, contentWidth - (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin() or 12) * 2)
    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    local fixedHeader = mf and mf.fixedHeader
    local headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
    local headerYOffset = (chrome and chrome.yOffset) or 0
    local scrollTopY = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
    local contentSide = (metrics and metrics.sideMargin) or SIDE_MARGIN
    
    -- Check if module is enabled (early check)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.reputations ~= false
    
    local COLORS = ns.UI_COLORS
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local tm = ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics() or {}
    local repRightReserve = (tm.edgeInset or 0)
    local searchH = PAGE_STACK.SEARCH_HEIGHT or 32
    -- Page stack: create + RepositionReputationFixedHeader both place chrome via UI_PageStack_Place.
    chrome = chrome or { headerParent = headerParent, yOffset = headerYOffset, side = contentSide }
    local hdrCache = mf and mf._wnReputationFixedHeaderCache
    local titleCard
    local headerChromeDone = false

    if hdrCache and hdrCache.titleCard and hdrCache.searchBox then
        titleCard = hdrCache.titleCard
        headerYOffset = RepositionReputationFixedHeader(hdrCache, headerParent, chrome, headerYOffset, contentSide, searchH)
        headerChromeDone = true
    end

    if not headerChromeDone then
    if mf and mf._wnReputationTitleCard then
        titleCard = mf._wnReputationTitleCard
        titleCard:Show()
    else
        titleCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
            tabKey = "reputation",
            titleText = "|cff" .. hexColor .. ((ns.L and ns.L["REP_TITLE"]) or "Reputation Overview") .. "|r",
            subtitleText = (ns.L and ns.L["REP_SUBTITLE"]) or "Track factions and renown across your warband",
            textRightInset = repRightReserve,
        }))
        if mf then
            mf._wnReputationTitleCard = titleCard
        end
    end
    
    -- View Mode: Always use Filtered View (All Characters view removed)
    
    titleCard:Show()

    if ns.UI_HideTitleCardExpandCollapseControls then
        ns.UI_HideTitleCardExpandCollapseControls(parent)
    end
    
    local titleH = (titleCard and titleCard:GetHeight()) or 0
    if titleH <= 0 then titleH = 64 end
    headerYOffset = ns.UI_PageStack_Place(chrome, titleCard, titleH)

    local CreateSearchBox = ns.UI_CreateSearchBox
    local reputationSearchText = SearchStateManager:GetQuery("reputation")
    
    local searchBox = CreateSearchBox(headerParent, contentWidth, (ns.L and ns.L["REP_SEARCH"]) or "Search reputations...", function(text)
        SearchStateManager:SetSearchQuery("reputation", text)
        if parent.resultsContainer then
            self:RedrawReputationResultsOnly(false)
        end
    end, nil, reputationSearchText, "reputation")
    
    headerYOffset = ns.UI_PageStack_Place(chrome, searchBox, searchH)

    if not hdrCache then
        hdrCache = {}
        if mf then mf._wnReputationFixedHeaderCache = hdrCache end
    end
    hdrCache.titleCard = titleCard
    hdrCache.searchBox = searchBox
    end -- not headerChromeDone

    if headerChromeDone and ns.UI_HideTitleCardExpandCollapseControls then
        ns.UI_HideTitleCardExpandCollapseControls(parent)
    end

    -- If module is disabled, show disabled state card in scroll area
    if not moduleEnabled then
        if ns.UI_HideTitleCardExpandCollapseControls then
            ns.UI_HideTitleCardExpandCollapseControls(parent)
        end
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) elseif fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, scrollTopY, (ns.L and ns.L["REP_DISABLED_TITLE"]) or "Reputation Tracking")
        return scrollTopY + cardHeight
    end

    -- Set fixedHeader height so scroll area starts below it
    if ns.UI_CommitTabFixedHeader then
        ns.UI_CommitTabFixedHeader(mf, headerYOffset)
    elseif fixedHeader then
        fixedHeader:SetHeight(headerYOffset)
    end
    
    -- Results Container (in scroll area)
    if not parent.resultsContainer then
        local container = ns.UI.Factory:CreateContainer(parent)
        parent.resultsContainer = container
    end
    
    local container = parent.resultsContainer
    container:SetParent(parent)
    ns.UI_PageStack_AnchorBody(parent, container, scrollTopY)
    container:SetWidth(bodyWidth)
    container:SetHeight(1)
    container:Show()
    
    local REP_LIST_DEFER_PLACEHOLDER_H = 120
    if parent._preparedByPopulate and not parent._wnRepListDeferScheduled then
        parent._wnRepListDeferScheduled = true
        local deferGen = mf and mf._tabSwitchGen or 0
        local deferSelf = self
        local deferParent = parent
        local deferContainer = container
        local deferBodyW = bodyWidth
        local deferScrollTopY = scrollTopY
        C_Timer.After(0, function()
            deferParent._wnRepListDeferScheduled = nil
            if not mf or mf.currentTab ~= "reputations" or mf._tabSwitchGen ~= deferGen then return end
            local listHeight = deferSelf:DrawReputationList(deferContainer, deferBodyW)
            ApplyReputationResultsHeight(mf, deferParent, deferContainer, listHeight, false)
            if ns.UI_SyncMainTabScrollChrome then
                ns.UI_SyncMainTabScrollChrome(mf, deferParent, deferScrollTopY + listHeight)
            end
        end)
        return deferScrollTopY + REP_LIST_DEFER_PLACEHOLDER_H
    end

    local listHeight = self:DrawReputationList(container, bodyWidth)
    ApplyReputationResultsHeight(WarbandNexus.UI and WarbandNexus.UI.mainFrame, parent, container, listHeight, false)
    
    return scrollTopY + listHeight
end

if ns.UI_RegisterTabViewportResize then
    ns.UI_RegisterTabViewportResize("reputations", {
        mode = ns.UI_VIEWPORT_RESIZE_MODE and ns.UI_VIEWPORT_RESIZE_MODE.RESULTS_CONTAINER,
        tabKey = "reputations",
        freezeWhileResizing = true,
        results = { bottomInset = 8 },
    })
end
