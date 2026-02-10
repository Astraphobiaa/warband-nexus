--[[
    Warband Nexus - Profession Detail Companion Panel
    Automatically appears next to WoW's profession UI when opened.
    Two modes: Compact (default, narrow) and Expanded (full detail).
    Uses storage system to show reagent availability across characters.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateIcon = ns.UI_CreateIcon
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

local L = ns.L
local function L_str(key, fallback)
    return (L and L[key]) or fallback or key
end

-- ============================================================================
-- LAYOUT CONSTANTS
-- ============================================================================
local FRAME_NAME = "WarbandNexus_ProfessionCompanion"

-- Compact mode (default)
local COMPACT_WIDTH = 300
local COMPACT_HEIGHT = 500
local COMPACT_CARD_HEIGHT = 28
local COMPACT_ICON_SIZE = 22

-- Expanded mode
local EXPANDED_WIDTH = 380
local EXPANDED_HEIGHT = 680
local EXPANDED_CARD_HEIGHT = 34
local EXPANDED_ICON_SIZE = 26

local PAD = 10
local SUMMARY_BAR_HEIGHT = 22
local RECIPE_CARD_GAP = 3

local expandedExpansions = {}
local isExpandedMode = false  -- compact by default

-- Fallback icons by profession name
local PROFESSION_FALLBACK_ICONS = {
    ["Alchemy"]        = "Interface\\Icons\\Trade_Alchemy",
    ["Blacksmithing"]  = "Interface\\Icons\\Trade_BlackSmithing",
    ["Enchanting"]     = "Interface\\Icons\\Trade_Engraving",
    ["Engineering"]    = "Interface\\Icons\\Trade_Engineering",
    ["Herbalism"]      = "Interface\\Icons\\Trade_Herbalism",
    ["Inscription"]    = "Interface\\Icons\\INV_Inscription_Tradeskill01",
    ["Jewelcrafting"]  = "Interface\\Icons\\INV_Misc_Gem_01",
    ["Leatherworking"] = "Interface\\Icons\\Trade_LeatherWorking",
    ["Mining"]         = "Interface\\Icons\\Trade_Mining",
    ["Skinning"]       = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    ["Tailoring"]      = "Interface\\Icons\\Trade_Tailoring",
    ["Cooking"]        = "Interface\\Icons\\INV_Misc_Food_15",
    ["Fishing"]        = "Interface\\Icons\\Trade_Fishing",
}
local DEFAULT_RECIPE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local currentProfessionName = nil

-- ============================================================================
-- DYNAMIC DIMENSION GETTERS
-- ============================================================================
local function GetWidth() return isExpandedMode and EXPANDED_WIDTH or COMPACT_WIDTH end
local function GetHeight() return isExpandedMode and EXPANDED_HEIGHT or COMPACT_HEIGHT end
local function GetCardHeight() return isExpandedMode and EXPANDED_CARD_HEIGHT or COMPACT_CARD_HEIGHT end
local function GetIconSize() return isExpandedMode and EXPANDED_ICON_SIZE or COMPACT_ICON_SIZE end
local function GetContentWidth() return GetWidth() - 12 end  -- 6px padding each side

-- ============================================================================
-- HELPERS
-- ============================================================================
local function GetRecipeIcon(icon)
    if icon and icon ~= "" and icon ~= 0 then return icon end
    if currentProfessionName and PROFESSION_FALLBACK_ICONS[currentProfessionName] then
        return PROFESSION_FALLBACK_ICONS[currentProfessionName]
    end
    return DEFAULT_RECIPE_ICON
end

local function GetCharNameFromKey(charKey)
    if not charKey then return "" end
    return charKey:match("^([^-]+)") or charKey
end

local function FormatTimeShort(sec)
    if not sec or sec <= 0 then return "Ready" end
    if sec < 60 then return string.format("%ds", math.floor(sec)) end
    if sec < 3600 then return string.format("%dm", math.floor(sec / 60)) end
    if sec < 86400 then return string.format("%.1fh", sec / 3600) end
    return string.format("%.1fd", sec / 86400)
end

local function GetClassColor(charKey)
    local char = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if char and char.classFile then
        local cc = RAID_CLASS_COLORS[char.classFile]
        if cc then return cc.r, cc.g, cc.b end
    end
    return 0.8, 0.8, 0.8
end

-- Shared formatters from ProfessionCacheService
local function TierTag(tierIdx)
    if ns.TierTag then return ns.TierTag(tierIdx) end
    -- Fallback: use ChatIcon atlas directly
    local atlas = "Professions-ChatIcon-Quality-Tier" .. tierIdx
    if CreateAtlasMarkup then return CreateAtlasMarkup(atlas, 0, 0) end
    return "|A:" .. atlas .. ":0:0|a"
end

local function TruncName(name, maxLen)
    if not name then return "?" end
    if #name <= maxLen then return name end
    return name:sub(1, maxLen - 2) .. ".."
end

-- ============================================================================
-- BUILD RECIPE TOOLTIP (with per-tier reagent availability)
-- Uses shared helpers from ProfessionCacheService, renders via ShowTooltip.
-- ============================================================================
local function BuildRecipeTooltip(anchorFrame, rec)
    if not ShowTooltip then return end
    local availability = WarbandNexus:GetReagentAvailability(rec.recipeID)
    local lines = {}

    if rec.cooldownRemaining and rec.cooldownRemaining > 0 then
        table.insert(lines, {
            left = "Cooldown:", right = FormatTimeShort(rec.cooldownRemaining),
            leftColor = {0.8, 0.8, 0.8}, rightColor = {1, 0.5, 0.3},
        })
    end
    if rec.charges and rec.charges.maxCharges and rec.charges.maxCharges > 0 then
        table.insert(lines, {
            left = "Charges:", right = string.format("%d / %d", rec.charges.currentCharges or 0, rec.charges.maxCharges),
            leftColor = {0.8, 0.8, 0.8}, rightColor = {0.5, 0.9, 0.5},
        })
    end

    local craftable = rec.craftableCount or 0
    table.insert(lines, {
        left = "Craftable:", right = tostring(craftable) .. "x",
        leftColor = {0.8, 0.8, 0.8},
        rightColor = craftable > 0 and {0.3, 1, 0.3} or {1, 0.4, 0.4},
    })

    if availability and #availability > 0 then
        table.insert(lines, {type = "spacer"})
        table.insert(lines, { left = "Reagents", leftColor = {1, 0.82, 0} })

        for _, a in ipairs(availability) do
            local need = a.quantityRequired or 1
            local baseName = TruncName(GetItemInfo(a.itemID) or ("Item " .. a.itemID), 22)
            local AmountColor = ns.AmountColor or function(amt) return amt > 0 and "44ff44" or "ff4444" end

            if a.tierAvailability and #a.tierAvailability > 1 then
                -- Reagent header: Name (left) | R1total R2total R3total /need (right)
                local tierParts = {}
                for _, tier in ipairs(a.tierAvailability) do
                    local have = tier.totalAvailable or 0
                    local col = AmountColor(have, need)
                    table.insert(tierParts, TierTag(tier.tierIndex) .. "|cff" .. col .. have .. "|r")
                end
                table.insert(lines, {
                    left = "|cffdadada" .. baseName .. "|r",
                    right = table.concat(tierParts, " ") .. " |cffaaaaaa/" .. need .. "|r",
                    leftColor = {1, 1, 1}, rightColor = {1, 1, 1},
                })

                -- Per-character (aggregate tiers per char)
                local charMap = {}
                local charOrder = {}
                for _, tier in ipairs(a.tierAvailability) do
                    if tier.characters then
                        for _, ch in ipairs(tier.characters) do
                            if ch.total and ch.total > 0 then
                                local key = ch.charName or "?"
                                if not charMap[key] then
                                    charMap[key] = { classFile = ch.classFile, counts = {} }
                                    table.insert(charOrder, key)
                                end
                                charMap[key].counts[tier.tierIndex] = (charMap[key].counts[tier.tierIndex] or 0) + ch.total
                            end
                        end
                    end
                end
                for _, charName in ipairs(charOrder) do
                    local info = charMap[charName]
                    local ClassColoredName = ns.ClassColoredName
                    local coloredName = ClassColoredName and ClassColoredName(charName, info.classFile) or charName
                    local charParts = {}
                    for _, tier in ipairs(a.tierAvailability) do
                        local count = info.counts[tier.tierIndex] or 0
                        local col = count > 0 and "ffffff" or "555555"
                        table.insert(charParts, TierTag(tier.tierIndex) .. "|cff" .. col .. count .. "|r")
                    end
                    table.insert(lines, {
                        left = coloredName,
                        right = table.concat(charParts, " "),
                        leftColor = {1, 1, 1}, rightColor = {1, 1, 1},
                    })
                end
            else
                -- Single-tier: Name (left) | have/need (right)
                local have = a.totalAvailable or 0
                local col = AmountColor(have, need)
                table.insert(lines, {
                    left = "|cffdadada" .. baseName .. "|r",
                    right = "|cff" .. col .. have .. "/" .. need .. "|r",
                    leftColor = {1, 1, 1}, rightColor = {1, 1, 1},
                })
                -- Per-character
                if a.characters then
                    for _, ch in ipairs(a.characters) do
                        if ch.total and ch.total > 0 then
                            local ClassColoredName = ns.ClassColoredName
                            local coloredName = ClassColoredName and ClassColoredName(ch.charName or "?", ch.classFile) or (ch.charName or "?")
                            table.insert(lines, {
                                left = coloredName,
                                right = "|cffffffff" .. ch.total .. "|r",
                                leftColor = {1, 1, 1}, rightColor = {1, 1, 1},
                            })
                        end
                    end
                end
            end
        end
    end

    ShowTooltip(anchorFrame, {
        type = "custom",
        icon = GetRecipeIcon(rec.icon),
        title = rec.name or ("Recipe " .. tostring(rec.recipeID)),
        lines = lines,
        anchor = "ANCHOR_RIGHT",
    })
end

-- ============================================================================
-- CREATE A RECIPE CARD
-- ============================================================================
local function CreateRecipeCard(parent, width, rec)
    local cardH = GetCardHeight()
    local iconSz = GetIconSize()

    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, cardH)
    card:EnableMouse(true)

    if ApplyVisuals then
        local borderAlpha = 0.35
        local craftable = rec.craftableCount or 0
        local onCD = rec.cooldownRemaining and rec.cooldownRemaining > 0
        local br, bg, bb = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
        if onCD then
            br, bg, bb = 0.9, 0.45, 0.2
        elseif craftable > 0 then
            br, bg, bb = 0.2, 0.8, 0.3
        elseif craftable == 0 then
            br, bg, bb = 0.6, 0.2, 0.2
        end
        ApplyVisuals(card, {0.06, 0.06, 0.08, 0.95}, {br, bg, bb, borderAlpha})
    end

    local iconFrame = card:CreateTexture(nil, "ARTWORK")
    iconFrame:SetSize(iconSz, iconSz)
    iconFrame:SetPoint("LEFT", 4, 0)
    iconFrame:SetTexture(GetRecipeIcon(rec.icon))
    iconFrame:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local nameText = FontManager:CreateFontString(card, "small", "OVERLAY")
    nameText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 5, -2)
    nameText:SetPoint("RIGHT", card, "RIGHT", -6, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetMaxLines(1)
    nameText:SetText(rec.name or "")
    nameText:SetTextColor(1, 1, 1)

    -- Status line (bottom-left) — only in expanded mode or if card is tall enough
    if cardH >= 30 then
        local craftable = rec.craftableCount or 0
        local statusParts = {}
        if rec.cooldownRemaining and rec.cooldownRemaining > 0 then
            table.insert(statusParts, "|cffff8844CD:" .. FormatTimeShort(rec.cooldownRemaining) .. "|r")
        end
        if craftable > 0 then
            table.insert(statusParts, string.format("|cff44ff44%dx|r", craftable))
        else
            table.insert(statusParts, "|cffff4444No mats|r")
        end

        local statusText = FontManager:CreateFontString(card, "small", "OVERLAY")
        statusText:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMRIGHT", 5, 1)
        statusText:SetJustifyH("LEFT")
        statusText:SetWordWrap(false)
        statusText:SetMaxLines(1)
        statusText:SetText(table.concat(statusParts, " "))

        -- Charges (bottom-right)
        if rec.charges and rec.charges.maxCharges and rec.charges.maxCharges > 0 then
            local chargeText = FontManager:CreateFontString(card, "small", "OVERLAY")
            chargeText:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -6, 2)
            chargeText:SetJustifyH("RIGHT")
            chargeText:SetText(string.format("|cff88ddaa%d/%d|r", rec.charges.currentCharges or 0, rec.charges.maxCharges))
        end
    end

    local highlight = card:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.04)

    card:SetScript("OnEnter", function(self) BuildRecipeTooltip(self, rec) end)
    card:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)

    return card
end

-- ============================================================================
-- RENDER RECIPE GRID
-- ============================================================================
local function RenderRecipeGrid(container, recipes, contentWidth, startY)
    if not recipes or #recipes == 0 then return 0 end
    local colWidth = contentWidth
    local cardH = GetCardHeight()
    local yDelta = 0

    for _, rec in ipairs(recipes) do
        local card = CreateRecipeCard(container, colWidth, rec)
        card:SetPoint("TOPLEFT", PAD, -(startY + yDelta))
        yDelta = yDelta + cardH + RECIPE_CARD_GAP
    end

    return yDelta
end

-- ============================================================================
-- REFRESH CONTENT
-- ============================================================================
local function RefreshContent(dialog, charKey, profSlot)
    local scrollChild = dialog._contentFrame
    if not scrollChild then return end

    -- Destroy previous inner container
    if dialog._innerContainer then
        dialog._innerContainer:Hide()
        dialog._innerContainer:SetParent(nil)
        dialog._innerContainer = nil
    end

    local explicitWidth = GetContentWidth()

    local container = CreateFrame("Frame", nil, scrollChild)
    container:SetPoint("TOPLEFT", 0, 0)
    container:SetWidth(explicitWidth)
    dialog._innerContainer = container

    local char = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    local prof = char and char.professions and char.professions[profSlot]
    if not prof then
        currentProfessionName = nil
        local emptyText = FontManager:CreateFontString(container, "body", "OVERLAY")
        emptyText:SetPoint("TOPLEFT", PAD, -PAD)
        emptyText:SetText("No profession data for this character.")
        emptyText:SetTextColor(0.7, 0.7, 0.7)
        container:SetHeight(60)
        scrollChild:SetHeight(60)
        return
    end

    currentProfessionName = prof.name

    local yOffset = 6
    local contentWidth = explicitWidth - 2 * PAD

    -- ── Title + Skill (left) | Timers + Concentration (right) ──
    local skillStr = ""
    if (prof.rank or prof.skill) and (prof.maxRank or prof.maxSkill) then
        skillStr = string.format("  |cff66dd66%d/%d|r", prof.rank or prof.skill, prof.maxRank or prof.maxSkill)
    end

    local titleLine = FontManager:CreateFontString(container, "subtitle", "OVERLAY")
    titleLine:SetPoint("TOPLEFT", PAD, -yOffset)
    titleLine:SetText((prof.name or "") .. skillStr)
    titleLine:SetTextColor(1, 0.82, 0)

    local cr, cg, cb = GetClassColor(charKey)
    local charLine = FontManager:CreateFontString(container, "small", "OVERLAY")
    charLine:SetPoint("TOPLEFT", PAD, -(yOffset + 14))
    charLine:SetText(GetCharNameFromKey(charKey))
    charLine:SetTextColor(cr, cg, cb)

    -- Right side: timers + concentration
    local rightY = yOffset
    local dailySec = (C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset) and C_DateAndTime.GetSecondsUntilDailyReset() or nil
    local weeklySec = (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset) and C_DateAndTime.GetSecondsUntilWeeklyReset() or nil

    if dailySec then
        local dt = FontManager:CreateFontString(container, "small", "OVERLAY")
        dt:SetPoint("TOPRIGHT", -PAD, -rightY)
        dt:SetJustifyH("RIGHT")
        dt:SetText("|cff99bbffD:|r " .. FormatTimeShort(dailySec))
        rightY = rightY + 11
    end
    if weeklySec then
        local wt = FontManager:CreateFontString(container, "small", "OVERLAY")
        wt:SetPoint("TOPRIGHT", -PAD, -rightY)
        wt:SetJustifyH("RIGHT")
        wt:SetText("|cff99bbffW:|r " .. FormatTimeShort(weeklySec))
        rightY = rightY + 11
    end

    -- Concentration
    local concData = nil
    local concCurrencyID = nil
    if prof.expansions then
        for _, exp in ipairs(prof.expansions) do
            if exp.concentration and exp.concentration.max and exp.concentration.max > 0 then
                concData = exp.concentration
                concCurrencyID = exp.concentration.currencyID
                break
            end
        end
    end
    local currentKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if concCurrencyID and charKey == currentKey and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local liveOk, liveInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, concCurrencyID)
        if liveOk and liveInfo then
            concData = { current = liveInfo.quantity or 0, max = liveInfo.maxQuantity or 0 }
        end
    end
    if concData and concData.max > 0 then
        local isFull = (concData.current or 0) >= concData.max
        local concColor = isFull and "|cff44ff44" or "|cffffaa44"
        local ct = FontManager:CreateFontString(container, "small", "OVERLAY")
        ct:SetPoint("TOPRIGHT", -PAD, -rightY)
        ct:SetJustifyH("RIGHT")
        ct:SetText("|cffddbbffC:|r " .. string.format("%s%d/%d|r", concColor, concData.current or 0, concData.max))
        rightY = rightY + 11
        if not isFull then
            local deficit = concData.max - (concData.current or 0)
            local timeToFull = (deficit / 250) * 86400
            local ft = FontManager:CreateFontString(container, "small", "OVERLAY")
            ft:SetPoint("TOPRIGHT", -PAD, -rightY)
            ft:SetJustifyH("RIGHT")
            ft:SetText("|cff666666" .. FormatTimeShort(timeToFull) .. "|r")
        end
    end

    yOffset = yOffset + 30

    -- ── Summary Bar (single line: Recipes | Craftable | CD) ──
    local allRecipes = WarbandNexus:GetRecipesForCharacterProfession(charKey, profSlot)
    local totalRecipes = allRecipes and #allRecipes or 0
    local craftableTotal, onCooldownTotal = 0, 0
    if allRecipes then
        for _, rec in ipairs(allRecipes) do
            if rec.craftableCount and rec.craftableCount > 0 then craftableTotal = craftableTotal + 1 end
            if rec.cooldownRemaining and rec.cooldownRemaining > 0 then onCooldownTotal = onCooldownTotal + 1 end
        end
    end

    local summaryBar = CreateFrame("Frame", nil, container)
    summaryBar:SetSize(contentWidth, SUMMARY_BAR_HEIGHT)
    summaryBar:SetPoint("TOPLEFT", PAD, -yOffset)
    if ApplyVisuals then
        local ac = COLORS.accent
        ApplyVisuals(summaryBar, {0.05, 0.05, 0.07, 0.95}, {ac[1], ac[2], ac[3], 0.4})
    end

    local summaryText = FontManager:CreateFontString(summaryBar, "small", "OVERLAY")
    summaryText:SetPoint("CENTER", 0, 0)
    summaryText:SetJustifyH("CENTER")
    local summaryStr = string.format(
        "|cffffcc00%d|r Recipes  |  |cff44ff44%d|r Craftable  |  |cffff8844%d|r CD",
        totalRecipes, craftableTotal, onCooldownTotal
    )
    summaryText:SetText(summaryStr)

    yOffset = yOffset + SUMMARY_BAR_HEIGHT + 6

    -- ── Hint if no scan ──
    local hasRecipeScan = prof.knownRecipes and #prof.knownRecipes > 0
    if not hasRecipeScan then
        local hint = FontManager:CreateFontString(container, "small", "OVERLAY")
        hint:SetPoint("TOPLEFT", PAD, -yOffset)
        hint:SetWidth(contentWidth)
        hint:SetWordWrap(true)
        hint:SetText("|cff88aaff[i] Open this profession to scan recipes.|r")
        hint:SetTextColor(0.5, 0.7, 1)
        yOffset = yOffset + 20
    end

    -- ── Expansion Sections ──
    local recipeByID = {}
    if allRecipes then
        for _, rec in ipairs(allRecipes) do
            recipeByID[rec.recipeID] = rec
        end
    end

    local expansionSkillInfo = {}
    if prof.expansions then
        for _, exp in ipairs(prof.expansions) do
            if exp.name then expansionSkillInfo[exp.name] = exp end
        end
    end

    local function FindExpSkillInfo(catName)
        if not catName then return nil end
        if expansionSkillInfo[catName] then return expansionSkillInfo[catName] end
        for expName, exp in pairs(expansionSkillInfo) do
            if catName:find(expName, 1, true) or expName:find(catName, 1, true) then
                return exp
            end
        end
        return nil
    end

    local sectionOrder = {}
    local sectionRecipes = {}

    if prof.expansionRecipes and next(prof.expansionRecipes) then
        for catName, recipeIDs in pairs(prof.expansionRecipes) do
            local enriched = {}
            for _, rid in ipairs(recipeIDs) do
                if recipeByID[rid] then table.insert(enriched, recipeByID[rid]) end
            end
            if #enriched > 0 then
                table.insert(sectionOrder, catName)
                sectionRecipes[catName] = enriched
            end
        end
        table.sort(sectionOrder, function(a, b)
            local expA = FindExpSkillInfo(a)
            local expB = FindExpSkillInfo(b)
            return (expA and expA.skillLine or 0) > (expB and expB.skillLine or 0)
        end)
    elseif allRecipes and #allRecipes > 0 then
        table.insert(sectionOrder, "All Recipes")
        sectionRecipes["All Recipes"] = allRecipes
    end

    for _, sectionName in ipairs(sectionOrder) do
        local recipes = sectionRecipes[sectionName]
        if not recipes or #recipes == 0 then break end

        local expInfo = FindExpSkillInfo(sectionName)
        local expKey = (charKey or "") .. "_" .. tostring(profSlot) .. "_" .. sectionName
        local isExpanded = expandedExpansions[expKey] == true

        local headerText
        if expInfo and expInfo.rank then
            headerText = string.format("%s  %d/%d  |cff888888(%d)|r",
                sectionName, expInfo.rank or 0, expInfo.maxRank or 100, #recipes)
        else
            headerText = string.format("%s  |cff888888(%d)|r", sectionName, #recipes)
        end

        local header = CreateCollapsibleHeader(
            container, headerText, expKey, isExpanded,
            function(expanded) expandedExpansions[expKey] = expanded; RefreshContent(dialog, charKey, profSlot) end,
            nil, false, 0
        )
        header:SetPoint("TOPLEFT", PAD, -yOffset)
        header:SetWidth(contentWidth)
        yOffset = yOffset + 30

        if isExpanded then
            if expInfo and expInfo.knowledgePoints and (expInfo.knowledgePoints.current or 0) > 0 then
                local kp = FontManager:CreateFontString(container, "small", "OVERLAY")
                kp:SetPoint("TOPLEFT", PAD + 12, -yOffset)
                kp:SetText("Knowledge: |cffaaaaff" .. tostring(expInfo.knowledgePoints.current) .. "|r")
                yOffset = yOffset + 13
            end

            if #recipes > 0 then
                yOffset = yOffset + 3
                local gridH = RenderRecipeGrid(container, recipes, contentWidth, yOffset)
                yOffset = yOffset + gridH
            end
            yOffset = yOffset + 3
        end
    end

    if #sectionOrder == 0 and hasRecipeScan then
        local hint = FontManager:CreateFontString(container, "small", "OVERLAY")
        hint:SetPoint("TOPLEFT", PAD, -yOffset)
        hint:SetWidth(contentWidth)
        hint:SetWordWrap(true)
        hint:SetText("|cff888888Re-open this profession to categorize recipes by expansion.|r")
        yOffset = yOffset + 16
    end

    dialog._charKey = charKey
    dialog._profSlot = profSlot

    local totalHeight = math.max(yOffset + 30, 200)
    container:SetHeight(totalHeight)
    scrollChild:SetWidth(explicitWidth)
    scrollChild:SetHeight(totalHeight)
end

-- ============================================================================
-- SMART POSITIONING: pick side with more space
-- ============================================================================
local function SmartPosition(dialog)
    dialog:ClearAllPoints()

    if not ProfessionsFrame or not ProfessionsFrame:IsShown() then
        dialog:SetPoint("CENTER")
        return
    end

    local screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale()
    local profRight = ProfessionsFrame:GetRight() or 0
    local profLeft = ProfessionsFrame:GetLeft() or 0
    local companionW = GetWidth()

    local spaceRight = screenWidth - profRight
    local spaceLeft = profLeft

    if spaceRight >= companionW + 4 then
        -- Enough room on the right
        dialog:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 2, 0)
    elseif spaceLeft >= companionW + 4 then
        -- Enough room on the left
        dialog:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPLEFT", -2, 0)
    else
        -- Not enough room on either side — overlap on the right edge
        dialog:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -4, -(ProfessionsFrame:GetTop() and (GetScreenHeight() * UIParent:GetEffectiveScale() - ProfessionsFrame:GetTop()) or 100))
    end
end

-- ============================================================================
-- COMPANION FRAME (singleton)
-- ============================================================================
local function GetOrCreateCompanionFrame()
    if _G[FRAME_NAME] then return _G[FRAME_NAME] end

    local dialog = CreateFrame("Frame", FRAME_NAME, UIParent)
    dialog:SetSize(GetWidth(), GetHeight())
    dialog:SetFrameStrata("HIGH")
    dialog:SetFrameLevel(10)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:Hide()

    if ApplyVisuals then
        ApplyVisuals(dialog, {0.05, 0.05, 0.07, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end

    -- Header bar
    local header = CreateFrame("Frame", nil, dialog)
    header:SetHeight(34)
    header:SetPoint("TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", -6, -6)
    if ApplyVisuals then
        ApplyVisuals(header, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4})
    end
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() dialog:StartMoving() end)
    header:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)

    -- Icon
    local iconTex = header:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(22, 22)
    iconTex:SetPoint("LEFT", 8, 0)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dialog._headerIcon = iconTex

    -- Title
    local titleFS = FontManager:CreateFontString(header, "small", "OVERLAY")
    titleFS:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
    titleFS:SetPoint("RIGHT", header, "RIGHT", -60, 0)
    titleFS:SetJustifyH("LEFT")
    titleFS:SetWordWrap(false)
    dialog._headerTitle = titleFS

    -- Toggle expand/compact button
    local toggleBtn = CreateFrame("Button", nil, header)
    toggleBtn:SetSize(22, 22)
    toggleBtn:SetPoint("RIGHT", -32, 0)
    if ApplyVisuals then
        ApplyVisuals(toggleBtn, {0.12, 0.12, 0.14, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    local toggleIcon = toggleBtn:CreateTexture(nil, "ARTWORK")
    toggleIcon:SetSize(14, 14)
    toggleIcon:SetPoint("CENTER")
    toggleIcon:SetAtlas(isExpandedMode and "UI-HUD-MicroMenu-Minimize-Up" or "UI-HUD-MicroMenu-Maximize-Up")
    toggleIcon:SetVertexColor(0.7, 0.9, 1)
    dialog._toggleIcon = toggleIcon

    toggleBtn:SetScript("OnClick", function()
        isExpandedMode = not isExpandedMode
        toggleIcon:SetAtlas(isExpandedMode and "UI-HUD-MicroMenu-Minimize-Up" or "UI-HUD-MicroMenu-Maximize-Up")

        -- Resize frame
        dialog:SetSize(GetWidth(), GetHeight())

        -- Update scroll child width
        local newCW = GetContentWidth()
        dialog._contentWidth = newCW
        if dialog._contentFrame then
            dialog._contentFrame:SetWidth(newCW)
        end

        -- Reposition smartly
        SmartPosition(dialog)

        -- Refresh content
        if dialog._charKey and dialog._profSlot then
            RefreshContent(dialog, dialog._charKey, dialog._profSlot)
        end
    end)
    toggleBtn:SetScript("OnEnter", function(self)
        if ApplyVisuals then ApplyVisuals(self, {0.18, 0.18, 0.22, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1}) end
    end)
    toggleBtn:SetScript("OnLeave", function(self)
        if ApplyVisuals then ApplyVisuals(self, {0.12, 0.12, 0.14, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}) end
    end)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", -6, 0)
    if ApplyVisuals then
        ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(12, 12)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)
    closeBtn:SetScript("OnEnter", function()
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ApplyVisuals then ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1}) end
    end)
    closeBtn:SetScript("OnLeave", function()
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ApplyVisuals then ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}) end
    end)

    -- Content area
    local contentArea = CreateFrame("Frame", nil, dialog)
    contentArea:SetPoint("TOPLEFT", 6, -42)
    contentArea:SetPoint("BOTTOMRIGHT", -6, 6)

    -- Scroll
    local scroll = CreateFrame("ScrollFrame", FRAME_NAME .. "Scroll", contentArea)
    scroll:SetAllPoints()
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxS = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * 40, maxS)))
    end)
    local CONTENT_W = GetContentWidth()
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(CONTENT_W)
    scrollChild:SetHeight(800)
    scroll:SetScrollChild(scrollChild)
    scroll:SetClipsChildren(true)

    dialog._contentFrame = scrollChild
    dialog._scroll = scroll
    dialog._contentWidth = CONTENT_W

    -- Auto-hide when profession frame closes
    dialog:SetScript("OnUpdate", function(self, elapsed)
        self._pollTimer = (self._pollTimer or 0) + elapsed
        if self._pollTimer < 0.5 then return end
        self._pollTimer = 0
        if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady or not C_TradeSkillUI.IsTradeSkillReady() then
            self:Hide()
        end
    end)

    return dialog
end

-- ============================================================================
-- SHOW / HIDE (public API)
-- ============================================================================
function WarbandNexus:ShowProfessionDetailWindow(charKey, profSlot, professionName, professionIcon)
    local dialog = GetOrCreateCompanionFrame()

    -- Update header
    dialog._headerTitle:SetText("|cffffffff" .. (professionName or "Profession") .. "|r")
    if professionIcon then
        dialog._headerIcon:SetTexture(professionIcon)
    end

    -- Ensure dimensions match current mode
    dialog:SetSize(GetWidth(), GetHeight())
    local newCW = GetContentWidth()
    dialog._contentWidth = newCW
    if dialog._contentFrame then
        dialog._contentFrame:SetWidth(newCW)
    end

    -- Smart position
    SmartPosition(dialog)

    RefreshContent(dialog, charKey, profSlot)
    dialog:Show()
end

function WarbandNexus:HideProfessionDetailWindow()
    local frame = _G[FRAME_NAME]
    if frame then frame:Hide() end
end

--[[
    Auto-show companion when profession UI opens.
    Called from EventManager after scan completes.
]]
function WarbandNexus:ShowProfessionCompanionForCurrentProfession()
    if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady() then return end

    local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo()
    if not baseInfo or not baseInfo.professionID then return end

    local charKey = ns.Utilities:GetCharacterKey()
    local professions = self.db.global.characters[charKey] and self.db.global.characters[charKey].professions
    if not professions then return end

    local profSlot = nil
    for i = 1, 2 do
        if professions[i] and professions[i].skillLine == baseInfo.professionID then
            profSlot = i
            break
        end
    end
    if not profSlot then
        if professions.cooking and professions.cooking.skillLine == baseInfo.professionID then
            profSlot = "cooking"
        end
    end
    if not profSlot then return end

    local prof = professions[profSlot]
    if not prof then return end

    self:ShowProfessionDetailWindow(charKey, profSlot, prof.name, prof.icon)
end

ns.ProfessionDetailWindow = true
