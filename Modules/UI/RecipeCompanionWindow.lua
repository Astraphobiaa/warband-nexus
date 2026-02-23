--[[
    Warband Nexus - Recipe Companion Window
    Companion panel anchored to ProfessionsFrame showing reagent availability
    per character with quality tier breakdown (Q1/Q2/Q3).
    
    Data flow:
    WN_RECIPE_SELECTED (from ProfessionService hook) → FetchReagentData() → Render rows
    WN_PROFESSION_WINDOW_OPENED  → Show companion (if ProfessionsFrame visible)
    WN_PROFESSION_WINDOW_CLOSED  → Hide companion
    BAG_UPDATE_DELAYED           → Refresh current recipe display (inventory changed)
    
    Frame hierarchy:
    UIParent
      └─ WarbandNexus_RecipeCompanion (HIGH strata, anchored to ProfessionsFrame)
           └─ Header (draggable: no)
           └─ contentArea
                └─ scrollFrame → scrollChild → reagent rows
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateIcon = ns.UI_CreateIcon
local Factory = ns.UI.Factory

-- Unique AceEvent handler identity for RecipeCompanionWindow
local RecipeCompanionEvents = {}

-- ── Layout constants ──
local PADDING = 8
local SCROLLBAR_GAP = 22
local HEADER_HEIGHT = 32
local WINDOW_WIDTH = 350
local ICON_SIZE = 20
local ROW_HEIGHT = 20
local SECTION_SPACING = 4
local REAGENT_HEADER_HEIGHT = 22
local MIN_FRAME_HEIGHT = 120
local MAX_FRAME_HEIGHT = 600

-- Quality tier atlas icons
local QUALITY_ATLAS = {
    "Professions-ChatIcon-Quality-Tier1",
    "Professions-ChatIcon-Quality-Tier2",
    "Professions-ChatIcon-Quality-Tier3",
}

-- ── State ──
local companionFrame = nil
local toggleTrackerBtn = nil       -- Button on ProfessionsFrame to toggle Recipe Companion
local currentRecipeID = nil
local currentReagentData = nil     -- Cached reagent data for current recipe
local pendingRefresh = false
local bagUpdateRegistered = false
local collapsedSlots = {}          -- { [slotIndex] = true } for collapsed reagent sections
local craftersSectionCollapsed = false  -- Collapse state for "Crafters" section

-- ============================================================================
-- REAGENT DATA EXTRACTION
-- ============================================================================

--[[
    Create atlas markup for quality tier icon.
    @param tierIdx number - 1, 2, or 3
    @return string - Atlas markup string
]]
-- Inline icon sizes for quality tier markup in font strings (pixels)
local ICON_INLINE = 16

-- Storage type icon sizes (real Texture frames — independent of font size)
local STORAGE_ICON = 16
local WARBAND_ICON_W = 16
local WARBAND_ICON_H = 16

-- Green checkmark texture for fulfilled reagents
local CHECK_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"

-- ── Row index counter (reset per render pass) ──
local rowCounter = 0

local function QualityTag(tierIdx)
    local atlas = QUALITY_ATLAS[tierIdx]
    if not atlas then return "" end
    if CreateAtlasMarkup then
        return CreateAtlasMarkup(atlas, ICON_INLINE, ICON_INLINE)
    end
    return "|A:" .. atlas .. ":" .. ICON_INLINE .. ":" .. ICON_INLINE .. "|a"
end

--[[
    Create a storage-type icon as a real Texture frame (bag, bank, warband).
    @param parent Frame - The row frame to attach the icon to
    @param atlas string - Atlas name (e.g. "bag-main")
    @param w number|nil - Width (defaults to STORAGE_ICON)
    @param h number|nil - Height (defaults to STORAGE_ICON)
    @return Texture
]]
local function CreateStorageIcon(parent, atlas, w, h)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas(atlas)
    icon:SetSize(w or STORAGE_ICON, h or STORAGE_ICON)
    icon:SetPoint("LEFT", PADDING + 10, 0)
    return icon
end

--[[
    Fetch reagent data for a recipe including per-character counts per quality tier.
    
    @param recipeID number
    @return table|nil - Array of reagent slot data:
    {
        {
            slotIndex     = number,
            reagentType   = number,      -- 0=Basic, 1=Optional, 2=Finishing
            required      = boolean,
            quantityRequired = number,
            reagents = {                 -- Array of tier items
                { itemID = number, name = string, tierIdx = number },
            },
            hasQuality    = boolean,     -- true if 2+ tiers exist
            counts = {
                total = { [tierIdx] = number },
                warband = { [tierIdx] = number },
                characters = {
                    { charName = string, classFile = string, counts = { [tierIdx] = number } },
                }
            }
        },
    }
]]
local function FetchReagentData(recipeID)
    if not recipeID then return nil end
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then return nil end

    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or not schematic or not schematic.reagentSlotSchematics then return nil end

    local slots = schematic.reagentSlotSchematics
    local result = {}

    for si = 1, #slots do
        local slot = slots[si]
        if not slot or not slot.reagents or #slot.reagents == 0 then
            -- skip empty slots
        else
            -- Quality tiers: only basic (0) and optional (1) with 2-3 variants
            -- Finishing reagents (2) with many alternatives are NOT quality tiers
            local isQualitySlot = (#slot.reagents >= 2 and #slot.reagents <= 3)

            local slotData = {
                slotIndex        = si,
                reagentType      = slot.reagentType or 0,
                required         = slot.required ~= false,
                quantityRequired = slot.quantityRequired or 0,
                reagents         = {},
                hasQuality       = isQualitySlot,
                isAlternatives   = (#slot.reagents > 3), -- finishing reagent alternatives
                counts           = {
                    total      = {},
                    warband    = {},
                    characters = {},
                },
            }

            -- Build tier item list
            for ti = 1, #slot.reagents do
                local reagent = slot.reagents[ti]
                if reagent and reagent.itemID then
                    local itemName = C_Item.GetItemNameByID(reagent.itemID)
                                  or (GetItemInfo and GetItemInfo(reagent.itemID))
                                  or ("Item " .. reagent.itemID)
                    slotData.reagents[#slotData.reagents + 1] = {
                        itemID  = reagent.itemID,
                        name    = itemName,
                        tierIdx = ti,
                    }
                end
            end

            -- Fetch per-character counts for each tier (bag and bank separate)
            local charMap = {}   -- [charName] = { classFile, bagCounts={}, bankCounts={} }
            local charOrder = {}

            for ti = 1, #slotData.reagents do
                local itemID = slotData.reagents[ti].itemID
                local details = WarbandNexus:GetDetailedItemCountsFast(itemID)

                local tierTotal = 0
                local wbCount = 0

                if details then
                    wbCount = details.warbandBank or 0
                    tierTotal = tierTotal + wbCount

                    for ci = 1, #details.characters do
                        local ch = details.characters[ci]
                        local bagCount  = ch.bagCount or 0
                        local bankCount = ch.bankCount or 0
                        tierTotal = tierTotal + bagCount + bankCount

                        if bagCount > 0 or bankCount > 0 then
                            local key = ch.charName or "?"
                            if not charMap[key] then
                                charMap[key] = { classFile = ch.classFile, bagCounts = {}, bankCounts = {} }
                                charOrder[#charOrder + 1] = key
                            end
                            charMap[key].bagCounts[ti]  = (charMap[key].bagCounts[ti] or 0) + bagCount
                            charMap[key].bankCounts[ti] = (charMap[key].bankCounts[ti] or 0) + bankCount
                        end
                    end
                end

                slotData.counts.total[ti] = tierTotal
                slotData.counts.warband[ti] = wbCount
            end

            -- Build character array with separate bag/bank counts
            for ci = 1, #charOrder do
                local name = charOrder[ci]
                local info = charMap[name]
                slotData.counts.characters[#slotData.counts.characters + 1] = {
                    charName   = name,
                    classFile  = info.classFile,
                    bagCounts  = info.bagCounts,
                    bankCounts = info.bankCounts,
                }
            end

            result[#result + 1] = slotData
        end
    end

    return result
end

-- ============================================================================
-- RENDERING
-- ============================================================================

--[[
    Sum all values in a numeric-keyed table.
    @param t table - { [key] = number }
    @return number
]]
local function SumCounts(t)
    local total = 0
    for _, v in pairs(t) do
        total = total + v
    end
    return total
end

--[[
    Create a 1px horizontal separator line.
    @param parent Frame
    @param yOffset number
    @param width number
    @return number - new yOffset after separator
]]
local function CreateSeparator(parent, yOffset, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", PADDING, -yOffset)
    line:SetPoint("RIGHT", parent, "RIGHT", -PADDING, 0)
    line:SetColorTexture(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.4)
    return yOffset + 1 + SECTION_SPACING
end

-- Fixed column width for each quality tier (icon + number + gap)
local TIER_COL_WIDTH = 38

--[[
    Render quality tier counts as fixed-position columns on a row frame.
    Each tier gets an icon (Texture) + count (FontString) at a fixed offset
    from the row's RIGHT edge, ensuring perfect vertical alignment across rows.
    
    Columns render right-to-left: tier N is rightmost, tier 1 is leftmost.
    @param parent Frame - The row frame
    @param counts table - { [tierIdx] = number }
    @param numTiers number - Total number of tiers (2 or 3)
]]
local function RenderQualityColumns(parent, counts, numTiers)
    for ti = numTiers, 1, -1 do
        local colOffset = -PADDING - (numTiers - ti) * TIER_COL_WIDTH
        local count = counts[ti] or 0

        -- Fixed-width column frame
        local col = CreateFrame("Frame", nil, parent)
        col:SetSize(TIER_COL_WIDTH, parent:GetHeight() or ROW_HEIGHT)
        col:SetPoint("RIGHT", parent, "RIGHT", colOffset, 0)
        col:Show()

        -- Icon at fixed LEFT position within column (always aligned)
        local icon = col:CreateTexture(nil, "ARTWORK")
        icon:SetAtlas(QUALITY_ATLAS[ti])
        icon:SetSize(ICON_INLINE, ICON_INLINE)
        icon:SetPoint("LEFT", 2, 0)

        -- Count text immediately after icon (tight gap)
        local countText = FontManager:CreateFontString(col, "body", "OVERLAY")
        countText:SetPoint("LEFT", icon, "RIGHT", 2, 0)

        if count > 0 then
            countText:SetText("|cffffffff" .. count .. "|r")
        else
            countText:SetText("|cffffffff-|r")
        end
    end
end

--[[
    Render all reagent rows into the scrollChild.
    Headers are collapsible (click to toggle), with green checkmark when fulfilled.
    @param scrollChild Frame - The scroll content frame
]]
local function RenderContent(scrollChild)
    if not scrollChild then return end

    -- Clear existing children (hide, don't destroy for reuse)
    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        children[i]:Hide()
        children[i]:ClearAllPoints()
    end
    -- Also hide loose font strings / textures from previous render
    local regions = { scrollChild:GetRegions() }
    for i = 1, #regions do
        regions[i]:Hide()
    end

    if not currentReagentData or #currentReagentData == 0 then
        local noData = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        noData:SetPoint("TOPLEFT", PADDING, -PADDING)
        noData:SetText("|cffffffff" .. ((ns.L and ns.L["SELECT_RECIPE"]) or "Select a recipe") .. "|r")
        noData:Show()
        scrollChild:SetHeight(40)
        return
    end

    local contentWidth = scrollChild:GetWidth()
    local yOffset = 4
    rowCounter = 0  -- Reset alternating row counter each render

    -- ========================================================================
    -- CRAFTERS SECTION — "Who Can Craft This?" (top of window)
    -- ========================================================================
    if currentRecipeID then
        local crafters = WarbandNexus:GetCraftersForRecipe(currentRecipeID)
        if crafters and #crafters > 0 then
            local function ToggleCrafters()
                craftersSectionCollapsed = not craftersSectionCollapsed
                RenderContent(scrollChild)
            end

            yOffset = Factory:CreateSectionHeader(
                scrollChild, yOffset, craftersSectionCollapsed,
                "|cff4488cc" .. ((ns.L and ns.L["CRAFTERS_SECTION"]) or "Crafters") .. "|r |cffffffff(" .. #crafters .. ")|r",
                nil, ToggleCrafters, REAGENT_HEADER_HEIGHT
            )

            -- Crafter rows (only when expanded)
            if not craftersSectionCollapsed then
                local bestIdx = 1

                for ci = 1, #crafters do
                    local crafter = crafters[ci]
                    local cc = RAID_CLASS_COLORS[crafter.classFile] or { r = 1, g = 1, b = 1 }
                    local classColor = string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)

                    rowCounter = rowCounter + 1
                    local crafterRow
                    crafterRow, yOffset = Factory:CreateDataRow(scrollChild, yOffset, rowCounter, ROW_HEIGHT)

                    -- Best crafter highlight overlay (on top of alternating bg)
                    if ci == bestIdx then
                        local highlightBg = crafterRow:CreateTexture(nil, "ARTWORK", nil, -8)
                        highlightBg:SetAllPoints()
                        highlightBg:SetColorTexture(0.15, 0.25, 0.10, 0.35)
                    end

                    local nameOffset = PADDING + 10
                    if ci == bestIdx then
                        local star = crafterRow:CreateTexture(nil, "ARTWORK")
                        star:SetAtlas("PetJournal-FavoritesIcon")
                        star:SetSize(12, 12)
                        star:SetPoint("LEFT", PADDING + 2, 0)
                        nameOffset = PADDING + 16
                    end

                    local nameText = FontManager:CreateFontString(crafterRow, "body", "OVERLAY")
                    nameText:SetPoint("LEFT", nameOffset, 0)
                    nameText:SetText(classColor .. crafter.charName .. "|r")

                    local concText = FontManager:CreateFontString(crafterRow, "body", "OVERLAY")
                    concText:SetPoint("RIGHT", crafterRow, "RIGHT", -PADDING, 0)
                    concText:SetJustifyH("RIGHT")

                    if crafter.concentration then
                        local estConc = WarbandNexus:GetEstimatedConcentration(crafter.concentration)
                        local maxConc = crafter.concentration.max or 0
                        local concColor
                        if maxConc > 0 and estConc >= maxConc * 0.8 then
                            concColor = "|cff44ff44"
                        elseif maxConc > 0 and estConc >= maxConc * 0.3 then
                            concColor = "|cffffcc00"
                        else
                            concColor = "|cffffffff"
                        end
                        concText:SetText(concColor .. estConc .. "/" .. maxConc .. "|r")
                    else
                        concText:SetText("|cffffffff-|r")
                    end

                    local skillText = FontManager:CreateFontString(crafterRow, "body", "OVERLAY")
                    skillText:SetPoint("RIGHT", concText, "LEFT", -8, 0)
                    skillText:SetJustifyH("RIGHT")

                    local skillColor = crafter.skillLevel >= crafter.maxSkillLevel and "|cff44ff44" or "|cffffcc00"
                    skillText:SetText(skillColor .. crafter.skillLevel .. "/" .. crafter.maxSkillLevel .. "|r")
                end
            end

            -- Separator after crafters section
            yOffset = CreateSeparator(scrollChild, yOffset + 2, contentWidth)
        end
    end

    for si = 1, #currentReagentData do
        local slot = currentReagentData[si]
        local numTiers = #slot.reagents

        -- Skip finishing reagent alternatives (many options, not quality tiers)
        if slot.isAlternatives then
            -- skip this slot entirely — finishing reagent with many alternatives
        else
            local totalHave = SumCounts(slot.counts.total)
            local needed = slot.quantityRequired
            local isSufficient = totalHave >= needed
            local isCollapsed = collapsedSlots[si]

            -- ── Reagent section header (collapsible, with border) ──
            local primaryName = slot.reagents[1] and slot.reagents[1].name or "Unknown"
            local namePrefix = isSufficient and (CHECK_ICON .. " ") or ""
            local nameColor = isSufficient and "|cff44ff44" or (totalHave > 0 and "|cffffcc00" or "|cffffffff")

            local function ToggleCollapse()
                collapsedSlots[si] = not collapsedSlots[si]
                RenderContent(scrollChild)
            end

            yOffset = Factory:CreateSectionHeader(
                scrollChild, yOffset, isCollapsed,
                namePrefix .. nameColor .. primaryName .. "|r",
                "|cffffffffx" .. needed .. "|r",
                ToggleCollapse, REAGENT_HEADER_HEIGHT
            )

            -- ── Child rows (only when expanded) ──
            if not isCollapsed then

                -- ── Per-character rows (separate bag / bank with atlas icons) ──
                for ci = 1, #slot.counts.characters do
                    local charInfo = slot.counts.characters[ci]
                    local bagTotal  = SumCounts(charInfo.bagCounts)
                    local bankTotal = SumCounts(charInfo.bankCounts)

                    if bagTotal > 0 or bankTotal > 0 then
                        local cc = RAID_CLASS_COLORS[charInfo.classFile] or { r = 1, g = 1, b = 1 }
                        local classColor = string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)

                        -- Bag row (inventory)
                        if bagTotal > 0 then
                            rowCounter = rowCounter + 1
                            local bagRow
                            bagRow, yOffset = Factory:CreateDataRow(scrollChild, yOffset, rowCounter, ROW_HEIGHT)

                            local bagIcon = CreateStorageIcon(bagRow, "Banker")
                            local bagNameText = FontManager:CreateFontString(bagRow, "body", "OVERLAY")
                            bagNameText:SetPoint("LEFT", bagIcon, "RIGHT", 4, 0)
                            bagNameText:SetText(classColor .. charInfo.charName .. "|r")

                            if slot.hasQuality then
                                RenderQualityColumns(bagRow, charInfo.bagCounts, numTiers)
                            else
                                local bagRightText = FontManager:CreateFontString(bagRow, "body", "OVERLAY")
                                bagRightText:SetPoint("RIGHT", bagRow, "RIGHT", -PADDING, 0)
                                bagRightText:SetJustifyH("RIGHT")
                                bagRightText:SetText("|cffffffff" .. bagTotal .. "|r")
                            end
                        end

                        -- Bank row
                        if bankTotal > 0 then
                            rowCounter = rowCounter + 1
                            local bankRow
                            bankRow, yOffset = Factory:CreateDataRow(scrollChild, yOffset, rowCounter, ROW_HEIGHT)

                            local bankIconTex = CreateStorageIcon(bankRow, "VignetteLoot")
                            local bankNameText = FontManager:CreateFontString(bankRow, "body", "OVERLAY")
                            bankNameText:SetPoint("LEFT", bankIconTex, "RIGHT", 4, 0)
                            bankNameText:SetText(classColor .. charInfo.charName .. "|r")

                            if slot.hasQuality then
                                RenderQualityColumns(bankRow, charInfo.bankCounts, numTiers)
                            else
                                local bankRightText = FontManager:CreateFontString(bankRow, "body", "OVERLAY")
                                bankRightText:SetPoint("RIGHT", bankRow, "RIGHT", -PADDING, 0)
                                bankRightText:SetJustifyH("RIGHT")
                                bankRightText:SetText("|cffffffff" .. bankTotal .. "|r")
                            end
                        end
                    end
                end

                -- ── Warband Bank row (only if > 0) ──
                local wbTotal = SumCounts(slot.counts.warband)
                if wbTotal > 0 then
                    rowCounter = rowCounter + 1
                    local wbRow
                    wbRow, yOffset = Factory:CreateDataRow(scrollChild, yOffset, rowCounter, ROW_HEIGHT)

                    local wbIconTex = CreateStorageIcon(wbRow, "warbands-icon", WARBAND_ICON_W, WARBAND_ICON_H)
                    local wbNameText = FontManager:CreateFontString(wbRow, "body", "OVERLAY")
                    wbNameText:SetPoint("LEFT", wbIconTex, "RIGHT", 4, 0)
                    wbNameText:SetText("|cffddaa44" .. ((ns.L and ns.L["ITEMS_WARBAND_BANK"]) or "Warband Bank") .. "|r")

                    if slot.hasQuality then
                        RenderQualityColumns(wbRow, slot.counts.warband, numTiers)
                    else
                        local wbRightText = FontManager:CreateFontString(wbRow, "body", "OVERLAY")
                        wbRightText:SetPoint("RIGHT", wbRow, "RIGHT", -PADDING, 0)
                        wbRightText:SetJustifyH("RIGHT")
                        wbRightText:SetText("|cffffffff" .. wbTotal .. "|r")
                    end
                end

                -- ── Total row ──
                rowCounter = rowCounter + 1
                local totalRow
                totalRow, yOffset = Factory:CreateDataRow(scrollChild, yOffset, rowCounter, ROW_HEIGHT)

                local totalColor = isSufficient and "|cff44ff44" or (totalHave > 0 and "|cffffcc00" or "|cffffffff")
                local totalLabel = FontManager:CreateFontString(totalRow, "body", "OVERLAY")
                totalLabel:SetPoint("LEFT", PADDING + 10, 0)
                totalLabel:SetText(totalColor .. ((ns.L and ns.L["TOTAL_REAGENTS"]) or "Total Reagents") .. "|r")

                if slot.hasQuality then
                    RenderQualityColumns(totalRow, slot.counts.total, numTiers)
                else
                    local totalRightText = FontManager:CreateFontString(totalRow, "body", "OVERLAY")
                    totalRightText:SetPoint("RIGHT", totalRow, "RIGHT", -PADDING, 0)
                    totalRightText:SetJustifyH("RIGHT")
                    totalRightText:SetText(totalColor .. totalHave .. "|r")
                end

            end -- end if not isCollapsed

            -- Spacing between reagent sections
            yOffset = yOffset + SECTION_SPACING
        end
    end

    -- Set scrollChild height and dynamic frame height
    local frame = companionFrame
    local scrollFrame = frame and frame.contentScrollFrame

    local totalContentHeight = yOffset + PADDING  -- scroll child content
    scrollChild:SetHeight(totalContentHeight)

    if frame then
        -- Full frame height = header + padding + content + padding
        local desiredFrameHeight = HEADER_HEIGHT + PADDING + totalContentHeight + PADDING

        -- Max height = ProfessionsFrame height (never taller than profession window)
        local maxHeight = MAX_FRAME_HEIGHT
        if ProfessionsFrame and ProfessionsFrame:IsShown() then
            maxHeight = ProfessionsFrame:GetHeight()
        end

        local frameHeight = math.max(MIN_FRAME_HEIGHT, math.min(desiredFrameHeight, maxHeight))
        frame:SetHeight(frameHeight)

        -- Viewport = frame height minus header and padding
        local viewportHeight = frameHeight - HEADER_HEIGHT - PADDING - PADDING
        local needsScroll = totalContentHeight > viewportHeight

        -- Scrollbar + buttons: show only when content overflows
        if scrollFrame then
            local scrollBar = scrollFrame.ScrollBar

            if needsScroll then
                if scrollBar then
                    scrollBar:Show()
                    if scrollBar.ScrollUpBtn  then scrollBar.ScrollUpBtn:Show() end
                    if scrollBar.ScrollDownBtn then scrollBar.ScrollDownBtn:Show() end
                end
                scrollFrame:SetPoint("TOPRIGHT", frame.contentArea, "TOPRIGHT", -SCROLLBAR_GAP, -PADDING)
            else
                if scrollBar then
                    scrollBar:Hide()
                    if scrollBar.ScrollUpBtn  then scrollBar.ScrollUpBtn:Hide() end
                    if scrollBar.ScrollDownBtn then scrollBar.ScrollDownBtn:Hide() end
                end
                scrollFrame:SetVerticalScroll(0)
                scrollFrame:SetPoint("TOPRIGHT", frame.contentArea, "TOPRIGHT", -PADDING, -PADDING)
            end

            if scrollFrame.UpdateScrollChildRect then
                scrollFrame:UpdateScrollChildRect()
            end
        end
    end
end

-- ============================================================================
-- REFRESH
-- ============================================================================

--[[
    Refresh companion window content (debounced).
]]
local function RefreshCompanion()
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0, function()
        pendingRefresh = false
        if not companionFrame or not companionFrame:IsShown() then return end
        if currentRecipeID then
            local ok, data = pcall(FetchReagentData, currentRecipeID)
            if ok then
                currentReagentData = data
            end
        end
        if companionFrame.contentScrollChild then
            RenderContent(companionFrame.contentScrollChild)
        end
    end)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

--[[
    Called when a recipe is selected in the profession UI.
    @param recipeInfo table - Contains recipeID, name, icon, etc.
]]
local function OnRecipeSelected(recipeInfo)
    if not recipeInfo or not recipeInfo.recipeID then return end
    if recipeInfo.recipeID == currentRecipeID then return end
    if WarbandNexus.db and WarbandNexus.db.profile.recipeCompanionEnabled == false then return end

    currentRecipeID = recipeInfo.recipeID
    collapsedSlots = {} -- Reset collapse state for new recipe
    craftersSectionCollapsed = false

    -- Update title
    if companionFrame and companionFrame.titleText then
        local recipeName = recipeInfo.name or "Recipe"
        companionFrame.titleText:SetText("|cffffffff" .. recipeName .. "|r")
    end

    RefreshCompanion()
end

--[[
    Create the "Toggle Tracker" button on ProfessionsFrame (once).
    Toggles recipeCompanionEnabled and shows/hides the Recipe Companion.
]]
local function EnsureToggleTrackerButton()
    if toggleTrackerBtn then return end
    if not ProfessionsFrame then return end

    local btn = Factory:CreateButton(ProfessionsFrame, 130, 24, false)
    btn:SetPoint("BOTTOMLEFT", ProfessionsFrame, "BOTTOMLEFT", 285, 5)
    if ApplyVisuals then
        ApplyVisuals(btn, { 0.05, 0.05, 0.07, 0.95 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
    label:SetPoint("CENTER", 0, 0)
    label:SetText((ns.L and ns.L["TOGGLE_TRACKER"]) or "Toggle Tracker")
    btn:SetScript("OnClick", function()
        if not WarbandNexus.db then return end
        WarbandNexus.db.profile.recipeCompanionEnabled = not (WarbandNexus.db.profile.recipeCompanionEnabled ~= false)
        if WarbandNexus.db.profile.recipeCompanionEnabled then
            if ns.RecipeCompanionWindow and ns.RecipeCompanionWindow.Show then
                ns.RecipeCompanionWindow.Show()
            end
        else
            if ns.RecipeCompanionWindow and ns.RecipeCompanionWindow.Hide then
                ns.RecipeCompanionWindow.Hide()
            end
        end
    end)
    toggleTrackerBtn = btn
end

--[[
    Called when profession window opens.
]]
local function OnProfessionWindowOpened()
    if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return end
    EnsureToggleTrackerButton()

    if not companionFrame then return end
    if WarbandNexus.db and WarbandNexus.db.profile.recipeCompanionEnabled == false then return end

    -- Calculate companion width
    local companionWidth = companionFrame:GetWidth() + 8

    -- Check if ProfessionsFrame needs to move right for companion to fit
    local profLeft = ProfessionsFrame:GetLeft() or 0

    if profLeft < companionWidth and not companionFrame._profMoved then
        -- Save ALL original anchor points (preserves Blizzard's anchor system)
        companionFrame._profOrigPoints = {}
        local numPoints = ProfessionsFrame:GetNumPoints()
        for i = 1, numPoints do
            local point, relativeTo, relativePoint, x, y = ProfessionsFrame:GetPoint(i)
            table.insert(companionFrame._profOrigPoints, {
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                x = x or 0,
                y = y or 0
            })
        end

        -- Shift all anchors right by exactly the amount needed
        local shiftAmount = companionWidth - profLeft
        ProfessionsFrame:ClearAllPoints()
        for _, p in ipairs(companionFrame._profOrigPoints) do
            ProfessionsFrame:SetPoint(p.point, p.relativeTo, p.relativePoint, p.x + shiftAmount, p.y)
        end
        companionFrame._profMoved = true
    end

    -- Anchor companion to the left of ProfessionsFrame
    companionFrame:ClearAllPoints()
    companionFrame:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPLEFT", -4, 0)
    companionFrame:Show()
end

--[[
    Called when profession window closes.
]]
local function OnProfessionWindowClosed()
    if companionFrame then
        companionFrame:Hide()
        -- Restore ALL original anchor points exactly as Blizzard set them
        if companionFrame._profMoved and companionFrame._profOrigPoints and ProfessionsFrame then
            ProfessionsFrame:ClearAllPoints()
            for _, p in ipairs(companionFrame._profOrigPoints) do
                ProfessionsFrame:SetPoint(p.point, p.relativeTo, p.relativePoint, p.x, p.y)
            end
        end
        companionFrame._profMoved = nil
        companionFrame._profOrigPoints = nil
    end
    currentRecipeID = nil
    currentReagentData = nil
end

-- ============================================================================
-- WINDOW CREATION
-- ============================================================================

--[[
    Create the companion window frame.
    Called once during initialization; frame is reused.
]]
local function CreateCompanionWindow()
    if companionFrame then return companionFrame end

    -- ── Main frame ──
    local frame = CreateFrame("Frame", "WarbandNexus_RecipeCompanion", UIParent)
    frame:SetSize(WINDOW_WIDTH, 400)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:Hide() -- Hidden until profession window opens

    if ApplyVisuals then
        ApplyVisuals(frame, { 0.04, 0.04, 0.06, 0.97 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7 })
    end

    -- ── Header ──
    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    if ApplyVisuals then
        ApplyVisuals(header, { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 },
            { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end

    -- Header icon (profession/recipe icon)
    local hIcon = header:CreateTexture(nil, "ARTWORK")
    hIcon:SetSize(18, 18)
    hIcon:SetPoint("LEFT", PADDING + 2, 0)
    hIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    frame.headerIcon = hIcon

    -- Title
    local titleText = FontManager:CreateFontString(header, "body", "OVERLAY")
    titleText:SetPoint("LEFT", hIcon, "RIGHT", 6, 0)
    titleText:SetPoint("RIGHT", header, "RIGHT", -PADDING, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    titleText:SetMaxLines(1)
    titleText:SetText("|cffffffff" .. ((ns.L and ns.L["RECIPE_COMPANION_TITLE"]) or "Recipe Companion") .. "|r")
    frame.titleText = titleText

    -- ── Content area ──
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    contentArea:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.contentArea = contentArea

    -- ── Scroll frame ──
    local scrollFrame = Factory:CreateScrollFrame(contentArea, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, -PADDING)
    scrollFrame:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -SCROLLBAR_GAP, -PADDING)
    scrollFrame:SetPoint("BOTTOM", contentArea, "BOTTOM", 0, PADDING)
    scrollFrame:EnableMouseWheel(true)
    frame.contentScrollFrame = scrollFrame

    -- Override Blizzard's OnScrollRangeChanged to prevent automatic scrollbar show.
    -- We control scrollbar visibility ourselves in RenderContent().
    scrollFrame:SetScript("OnScrollRangeChanged", function(self, xRange, yRange)
        -- Only update scroll position to keep it in valid range
        if yRange and yRange > 0 then
            local currentScroll = self:GetVerticalScroll()
            if currentScroll > yRange then
                self:SetVerticalScroll(yRange)
            end
        else
            self:SetVerticalScroll(0)
        end
        -- Do NOT show/hide scrollbar here — RenderContent handles it
    end)

    -- Initially hide scrollbar components until RenderContent decides
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:Hide()
        if scrollFrame.ScrollBar.ScrollUpBtn then scrollFrame.ScrollBar.ScrollUpBtn:Hide() end
        if scrollFrame.ScrollBar.ScrollDownBtn then scrollFrame.ScrollBar.ScrollDownBtn:Hide() end
    end

    -- Scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(1) -- Updated dynamically
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.contentScrollChild = scrollChild

    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 16
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = math.max(0, math.min(current - (delta * step), maxScroll))
        self:SetVerticalScroll(newScroll)
    end)

    -- ── Escape key (combat-safe: SetPropagateKeyboardInput is protected in 12.0) ──
    local function SetupKeyboard()
        if InCombatLockdown() then return false end
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
        frame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
                self:Hide()
            else
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end
        end)
        return true
    end
    if not SetupKeyboard() then
        local kbDefer = CreateFrame("Frame")
        kbDefer:RegisterEvent("PLAYER_REGEN_ENABLED")
        kbDefer:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            SetupKeyboard()
        end)
    end

    -- ── OnShow: update scrollChild width ──
    frame:SetScript("OnShow", function(self)
        local sw = scrollFrame:GetWidth()
        if sw and sw > 0 then
            scrollChild:SetWidth(sw)
        end
    end)

    companionFrame = frame
    return frame
end

-- ============================================================================
-- INITIALIZATION (called from EventManager after events are wired)
-- ============================================================================

function WarbandNexus:InitializeRecipeCompanion()
    -- Create the frame (hidden)
    CreateCompanionWindow()

    -- NOTE: Uses RecipeCompanionEvents as 'self' key to avoid overwriting other modules' handlers.
    -- Listen for recipe selection (guard with module check)
    WarbandNexus.RegisterMessage(RecipeCompanionEvents, "WN_RECIPE_SELECTED", function(_, recipeInfo)
        if not ns.Utilities:IsModuleEnabled("professions") then return end
        OnRecipeSelected(recipeInfo)
    end)

    -- Listen for profession window lifecycle (guard with module check)
    WarbandNexus.RegisterMessage(RecipeCompanionEvents, "WN_PROFESSION_WINDOW_OPENED", function()
        if not ns.Utilities:IsModuleEnabled("professions") then return end
        OnProfessionWindowOpened()
    end)

    WarbandNexus.RegisterMessage(RecipeCompanionEvents, "WN_PROFESSION_WINDOW_CLOSED", function()
        OnProfessionWindowClosed()
    end)

    -- BAG_UPDATE_DELAYED: refresh counts when inventory changes (guard with module check)
    -- CRITICAL FIX: Uses RecipeCompanionEvents as 'self' key so we don't overwrite
    -- ItemsCacheService's BAG_UPDATE_DELAYED → OnInventoryBagsChanged handler.
    if not bagUpdateRegistered then
        bagUpdateRegistered = true
        WarbandNexus.RegisterEvent(RecipeCompanionEvents, "BAG_UPDATE_DELAYED", function()
            if not ns.Utilities:IsModuleEnabled("professions") then return end
            if companionFrame and companionFrame:IsShown() and currentRecipeID then
                RefreshCompanion()
            end
        end)
    end

    -- WN_RECIPE_DATA_UPDATED: refresh when recipe scan completes (guard with module check)
    WarbandNexus.RegisterMessage(RecipeCompanionEvents, "WN_RECIPE_DATA_UPDATED", function()
        if not ns.Utilities:IsModuleEnabled("professions") then return end
        if companionFrame and companionFrame:IsShown() and currentRecipeID then
            RefreshCompanion()
        end
    end)

    if self.Debug then
        self:Debug("[RecipeCompanion] Initialized")
    end
end

-- ============================================================================
-- EXPORT
-- ============================================================================

ns.RecipeCompanionWindow = {
    Show = function()
        if companionFrame and not (WarbandNexus.db and WarbandNexus.db.profile.recipeCompanionEnabled == false) then
            OnProfessionWindowOpened()
        end
    end,
    Hide = function()
        if companionFrame then
            OnProfessionWindowClosed()
        end
    end,
    Refresh = RefreshCompanion,
}
