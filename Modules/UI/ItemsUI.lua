--[[
    Warband Nexus - Items Tab
    Display and manage Warband and Personal bank items with interactive controls
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Feature Flags
local ENABLE_GUILD_BANK = false -- Set to true when ready to enable Guild Bank features

-- Import shared UI components (always get fresh reference)
local COLORS = ns.UI_COLORS
local GetQualityHex = ns.UI_GetQualityHex
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local GetTypeIcon = ns.UI_GetTypeIcon
local DrawEmptyState = ns.UI_DrawEmptyState
local AcquireItemRow = ns.UI_AcquireItemRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateStatsBar = ns.UI_CreateStatsBar
local CreateResultsContainer = ns.UI_CreateResultsContainer
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor
local FormatNumber = ns.UI_FormatNumber

-- Import shared UI layout constants
local UI_LAYOUT = ns.UI_LAYOUT
local BASE_INDENT = UI_LAYOUT.BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = UI_LAYOUT.SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = UI_LAYOUT.SIDE_MARGIN or 10
local TOP_MARGIN = UI_LAYOUT.TOP_MARGIN or 8
local ROW_HEIGHT = UI_LAYOUT.ROW_HEIGHT or 26
local ROW_SPACING = UI_LAYOUT.ROW_SPACING or 26
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING or 40
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING or 8
local ROW_COLOR_EVEN = UI_LAYOUT.ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
local ROW_COLOR_ODD = UI_LAYOUT.ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}

-- Performance: Local function references
local format = string.format
local date = date

-- Module-level state (shared with main UI.lua via namespace)
-- State is accessed via ns.UI_GetItemsSubTab(), SearchStateManager, etc.

--============================================================================
-- DRAW ITEM LIST (Main Items Tab)
--============================================================================

function WarbandNexus:DrawItemList(parent)
    self.recentlyExpanded = self.recentlyExpanded or {}
    local yOffset = 8 -- Top padding for consistency with other tabs
    local width = parent:GetWidth() - 20 -- Match header padding (10 left + 10 right)
    
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    
    -- PERFORMANCE: Release pooled frames back to pool before redrawing
    ReleaseAllPooledChildren(parent)
    
    -- ===== HEADER CARD (Always shown) =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Header icon with ring border (standardized)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("items"))
    
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    -- Use factory pattern positioning for standardized header layout
    local titleTextContent = "|cff" .. hexColor .. "Bank Items|r"
    local subtitleTextContent = "Browse your Warband Bank and Personal Items (Bank + Inventory)"
    
    -- Create container for text group (using Factory pattern)
    local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)
    
    -- Create title text (header font, colored)
    local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
    titleText:SetText(titleTextContent)
    titleText:SetJustifyH("LEFT")
    
    -- Create subtitle text
    local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
    subtitleText:SetText(subtitleTextContent)
    subtitleText:SetTextColor(1, 1, 1)  -- White
    subtitleText:SetJustifyH("LEFT")
    
    -- Position texts: label at CENTER (0px), value at CENTER (-4px) - matching factory pattern
    titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)  -- Label at center
    titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)  -- Value below center
    subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    
    -- Position container: LEFT from icon, CENTER vertically to CARD (no checkbox)
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)  -- Center to card!
    
    titleCard:Show()
    
    yOffset = yOffset + UI_LAYOUT.afterHeader  -- Standard spacing after title card
    
    -- Check if module is disabled - show beautiful disabled state card
    if not ns.Utilities:IsModuleEnabled("items") then
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, "Warband Bank Items")
        return yOffset + cardHeight
    end
    
    -- Get state from namespace (managed by main UI.lua)
    local currentItemsSubTab = ns.UI_GetItemsSubTab()
    local itemsSearchText = SearchStateManager:GetQuery("items")
    local expandedGroups = ns.UI_GetExpandedGroups()
    
    -- ===== SUB-TAB BUTTONS (using Factory pattern) =====
    local tabFrame = ns.UI.Factory:CreateContainer(parent)
    tabFrame:SetHeight(32)
    tabFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    tabFrame:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Get theme colors
    local tabActiveColor = COLORS.tabActive
    local tabInactiveColor = COLORS.tabInactive
    local accentColor = COLORS.accent
    
    -- PERSONAL BANK BUTTON (using Factory pattern)
    local personalBtn = ns.UI.Factory:CreateButton(tabFrame, 130, 28)
    personalBtn:SetPoint("LEFT", 0, 0)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(personalBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    -- Apply highlight effect (safe check for Factory)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(personalBtn)
    end
    
    local personalText = FontManager:CreateFontString(personalBtn, "body", "OVERLAY")
    personalText:SetPoint("CENTER")
    personalText:SetText("Personal Items")
    personalText:SetTextColor(1, 1, 1)  -- Fixed white color
    
    personalBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("personal")  -- Switch to Personal Items (Bank + Inventory)
        WarbandNexus:RefreshUI()
    end)
    
    -- WARBAND BANK BUTTON (using Factory pattern)
    local warbandBtn = ns.UI.Factory:CreateButton(tabFrame, 130, 28)
    warbandBtn:SetPoint("LEFT", personalBtn, "RIGHT", 8, 0)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(warbandBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    -- Apply highlight effect (safe check for Factory)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(warbandBtn)
    end
    
    local warbandText = FontManager:CreateFontString(warbandBtn, "body", "OVERLAY")
    warbandText:SetPoint("CENTER")
    warbandText:SetText("Warband Bank")
    warbandText:SetTextColor(1, 1, 1)  -- Fixed white color
    
    warbandBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("warband")  -- Switch to Warband Bank tab
        WarbandNexus:RefreshUI()
    end)
    
    -- GUILD BANK BUTTON (Third/Right) - DISABLED BY DEFAULT
    if ENABLE_GUILD_BANK then
        local guildBtn = ns.UI.Factory:CreateButton(tabFrame, 130, 28)
        guildBtn:SetPoint("LEFT", warbandBtn, "RIGHT", 8, 0)
        
        -- No backdrop (naked frame)
        
        local guildText = FontManager:CreateFontString(guildBtn, "body", "OVERLAY")
        guildText:SetPoint("CENTER")
        guildText:SetText("Guild Bank")
        guildText:SetTextColor(1, 1, 1)  -- Fixed white color
        
        -- Check if player is in a guild
        local isInGuild = IsInGuild()
        if not isInGuild then
            guildBtn:Disable()
            guildBtn:SetAlpha(0.5)
            guildText:SetTextColor(1, 1, 1)  -- White
        end
        
        guildBtn:SetScript("OnClick", function()
            if not isInGuild then
                WarbandNexus:Print("|cffff6600You must be in a guild to access Guild Bank.|r")
                return
            end
            ns.UI_SetItemsSubTab("guild")  -- Switch to Guild Bank tab
            WarbandNexus:RefreshUI()
        end)
        -- Hover effects removed (no backdrop)
    end -- ENABLE_GUILD_BANK
    
    -- Update tab button borders based on active state
    if UpdateBorderColor then
        if currentItemsSubTab == "personal" then
            -- Active state - full accent color
            UpdateBorderColor(personalBtn, {accentColor[1], accentColor[2], accentColor[3], 1})
            if personalBtn.SetBackdropColor then
                personalBtn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1)
            end
        else
            -- Inactive state - dimmed accent color
            UpdateBorderColor(personalBtn, {accentColor[1] * 0.6, accentColor[2] * 0.6, accentColor[3] * 0.6, 1})
            if personalBtn.SetBackdropColor then
                personalBtn:SetBackdropColor(0.12, 0.12, 0.15, 1)
            end
        end
        
        if currentItemsSubTab == "warband" then
            -- Active state - full accent color
            UpdateBorderColor(warbandBtn, {accentColor[1], accentColor[2], accentColor[3], 1})
            if warbandBtn.SetBackdropColor then
                warbandBtn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1)
            end
        else
            -- Inactive state - dimmed accent color
            UpdateBorderColor(warbandBtn, {accentColor[1] * 0.6, accentColor[2] * 0.6, accentColor[3] * 0.6, 1})
            if warbandBtn.SetBackdropColor then
                warbandBtn:SetBackdropColor(0.12, 0.12, 0.15, 1)
            end
        end
    end
    
    -- ===== GOLD CONTROLS (Warband Bank ONLY) =====
    if currentItemsSubTab == "warband" then
        -- Gold display for Warband Bank
        local goldDisplay = FontManager:CreateFontString(tabFrame, "body", "OVERLAY")
        goldDisplay:SetPoint("RIGHT", tabFrame, "RIGHT", -10, 0)
        local warbandGold = WarbandNexus:GetWarbandBankMoney() or 0
        -- Use UI_FormatMoney for consistent formatting with icons
        local FormatMoney = ns.UI_FormatMoney
        if FormatMoney then
            goldDisplay:SetText(FormatMoney(warbandGold, 14))
        else
            goldDisplay:SetText(WarbandNexus:API_FormatMoney(warbandGold))
        end
    end
    -- Personal Bank has no gold controls (WoW doesn't support gold storage in personal bank)
    
    yOffset = yOffset + 32 + UI_LAYOUT.afterElement  -- Tab frame height + spacing
    
    -- ===== SEARCH BOX (Below sub-tabs) =====
    local CreateSearchBox = ns.UI_CreateSearchBox
    -- Use SearchStateManager for state management
    local itemsSearchText = SearchStateManager:GetQuery("items")
    
    local searchBox = CreateSearchBox(parent, width, "Search items...", function(text)
        -- Update search state via SearchStateManager (throttled, event-driven)
        SearchStateManager:SetSearchQuery("items", text)
        
        -- Prepare container for rendering
        local resultsContainer = parent.resultsContainer
        if resultsContainer then
            SearchResultsRenderer:PrepareContainer(resultsContainer)
            
            -- Redraw results with new search text
            local contentHeight = WarbandNexus:DrawItemsResults(resultsContainer, 0, width, ns.UI_GetItemsSubTab(), text)
            
            -- Update state with result count
            resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
        end
    end, 0.4, itemsSearchText)
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + 32 + UI_LAYOUT.afterElement  -- Search box height + spacing
    
    -- ===== STATS BAR =====
    -- Get items for stats (before results container)
    local items = {}
    if currentItemsSubTab == "warband" then
        items = self:GetWarbandBankItems() or {}
    elseif currentItemsSubTab == "guild" then
        items = self:GetGuildBankItems() or {}
    else
        items = self:GetPersonalBankItems() or {}
    end
    
    local statsBar, statsText = CreateStatsBar(parent, 24)
    statsBar:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    statsBar:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    local bankStats = self:GetBankStatistics()
    
    if currentItemsSubTab == "warband" then
        local wb = bankStats.warband or {}
        statsText:SetText(string.format("|cffa335ee%s items|r  •  %s/%s slots  •  Last: %s",
            FormatNumber(#items), FormatNumber(wb.usedSlots or 0), FormatNumber(wb.totalSlots or 0),
            (wb.lastScan or 0) > 0 and date("%H:%M", wb.lastScan) or "Never"))
    elseif currentItemsSubTab == "guild" then
        local gb = bankStats.guild or {}
        statsText:SetText(string.format("|cff00ff00%s items|r  •  %s/%s slots  •  Last: %s",
            FormatNumber(#items), FormatNumber(gb.usedSlots or 0), FormatNumber(gb.totalSlots or 0),
            (gb.lastScan or 0) > 0 and date("%H:%M", gb.lastScan) or "Never"))
    else
        -- Personal Items = Bank + Inventory
        local pb = bankStats.personal or {}
        local bagsData = self.db.char.bags or { usedSlots = 0, totalSlots = 0, lastScan = 0 }
        local combinedUsed = (pb.usedSlots or 0) + (bagsData.usedSlots or 0)
        local combinedTotal = (pb.totalSlots or 0) + (bagsData.totalSlots or 0)
        local lastScan = math.max(pb.lastScan or 0, bagsData.lastScan or 0)
        statsText:SetText(string.format("|cff88ff88%s items|r  •  %s/%s slots  •  Last: %s",
            FormatNumber(#items), FormatNumber(combinedUsed), FormatNumber(combinedTotal),
            lastScan > 0 and date("%H:%M", lastScan) or "Never"))
    end
    statsText:SetTextColor(1, 1, 1)  -- White (9/196 slots - Last updated)
    
    yOffset = yOffset + 24 + UI_LAYOUT.afterElement  -- Stats bar height + spacing
    
    -- ===== RESULTS CONTAINER (After stats bar) =====
    local resultsContainer = CreateResultsContainer(parent, yOffset, SIDE_MARGIN)
    parent.resultsContainer = resultsContainer  -- Store reference for search callback
    
    -- Initial draw of results
    local contentHeight = self:DrawItemsResults(resultsContainer, 0, width, currentItemsSubTab, itemsSearchText)
    
    -- CRITICAL FIX: Update container height AFTER content is drawn
    resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
    
    return yOffset + (contentHeight or 0)
end

--============================================================================
-- ITEMS RESULTS RENDERING (Separated for search refresh)
--============================================================================

function WarbandNexus:DrawItemsResults(parent, yOffset, width, currentItemsSubTab, itemsSearchText)
    local expandedGroups = ns.UI_GetExpandedGroups()
    
    -- Get items based on selected sub-tab
    local items = {}
    if currentItemsSubTab == "warband" then
        items = self:GetWarbandBankItems() or {}
    elseif currentItemsSubTab == "guild" then
        items = self:GetGuildBankItems() or {}
    else
        -- Personal Items = Bank + Inventory combined
        items = self:GetPersonalBankItems() or {}
    end
    
    -- Apply search filter (Items tab specific)
    if itemsSearchText and itemsSearchText ~= "" then
        local filtered = {}
        for _, item in ipairs(items) do
            local itemName = (item.name or ""):lower()
            local itemLink = (item.itemLink or ""):lower()
            if itemName:find(itemsSearchText, 1, true) or itemLink:find(itemsSearchText, 1, true) then
                table.insert(filtered, item)
            end
        end
        items = filtered
    end
    
    -- Sort items alphabetically by name
    table.sort(items, function(a, b)
        local nameA = (a.name or ""):lower()
        local nameB = (b.name or ""):lower()
        return nameA < nameB
    end)
    
    -- ===== EMPTY STATE =====
    if #items == 0 then
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, itemsSearchText, "items")
        -- Update SearchStateManager with result count
        SearchStateManager:UpdateResults("items", 0)
        return height
    end
    
    -- Update SearchStateManager with result count (after filtering)
    SearchStateManager:UpdateResults("items", #items)
    
    -- ===== GROUP ITEMS BY TYPE =====
    local groups = {}
    local groupOrder = {}
    local hasSearchFilter = itemsSearchText and itemsSearchText ~= ""
    
    for _, item in ipairs(items) do
        local typeName = item.itemType or "Miscellaneous"
        if not groups[typeName] then
            local groupKey = currentItemsSubTab .. "_" .. typeName
            
            -- Auto-expand if search is active, otherwise use persisted state
            if hasSearchFilter then
                expandedGroups[groupKey] = true
            elseif expandedGroups[groupKey] == nil then
                expandedGroups[groupKey] = true
            end
            
            groups[typeName] = { name = typeName, items = {}, groupKey = groupKey }
            table.insert(groupOrder, typeName)
        end
        table.insert(groups[typeName].items, item)
    end
    
    -- Sort group names alphabetically
    table.sort(groupOrder)
    
    -- ===== DRAW GROUPS =====
    local rowIdx = 0
    for _, typeName in ipairs(groupOrder) do
        local group = groups[typeName]
        local isExpanded = self.itemsExpandAllActive or expandedGroups[group.groupKey]
        
        -- Get icon from first item in group
        local typeIcon = nil
        if group.items[1] and group.items[1].classID then
            typeIcon = GetTypeIcon(group.items[1].classID)
        end
        
        -- Toggle function for this group
        local gKey = group.groupKey
        local function ToggleGroup(key, isExpanded)
            -- Use isExpanded if provided (new style), otherwise toggle (old style)
            if type(isExpanded) == "boolean" then
                expandedGroups[key] = isExpanded
                if isExpanded then self.recentlyExpanded[key] = GetTime() end
            else
                expandedGroups[key] = not expandedGroups[key]
                if expandedGroups[key] then self.recentlyExpanded[key] = GetTime() end
            end
            WarbandNexus:RefreshUI()
        end
        
        -- Create collapsible header with purple border and icon
        local groupHeader, expandBtn = CreateCollapsibleHeader(
            parent,
            format("%s (%s)", typeName, FormatNumber(#group.items)),
            gKey,
            isExpanded,
            function(isExpanded) ToggleGroup(gKey, isExpanded) end,
            typeIcon
        )
        groupHeader:SetPoint("TOPLEFT", 0, -yOffset)
        groupHeader:SetWidth(width)  -- Set width to match content area
        
        yOffset = yOffset + UI_LAYOUT.HEADER_HEIGHT  -- Header (no extra spacing before rows)
        
        -- Draw items in this group (if expanded)
        if isExpanded then
            local shouldAnimate = self.recentlyExpanded[gKey] and (GetTime() - self.recentlyExpanded[gKey] < 0.5)
            local animIdx = 0
            
            for _, item in ipairs(group.items) do
                rowIdx = rowIdx + 1
                animIdx = animIdx + 1
                local i = rowIdx
                
                -- PERFORMANCE: Acquire from pool instead of creating new
                local row = AcquireItemRow(parent, width, ROW_HEIGHT)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -yOffset)  -- Items tab has NO subheaders, rows at 0px is correct
                
                -- Ensure alpha is reset (pooling safety)
                row:SetAlpha(1)
                
                -- Stop any previous animations
                if row.anim then row.anim:Stop() end
                
                -- Smart Animation
                if shouldAnimate then
                    row:SetAlpha(0)
                    
                    -- Reuse animation objects to prevent leaks
                    if not row.anim then
                        local anim = row:CreateAnimationGroup()
                        local fade = anim:CreateAnimation("Alpha")
                        fade:SetSmoothing("OUT")
                        anim:SetScript("OnFinished", function() row:SetAlpha(1) end)
                        
                        row.anim = anim
                        row.fade = fade
                    end
                    
                    row.fade:SetFromAlpha(0)
                    row.fade:SetToAlpha(1)
                    row.fade:SetDuration(0.15)
                    row.fade:SetStartDelay(animIdx * 0.05) -- Stagger relative to group start
                    
                    row.anim:Play()
                end
                row.idx = i
                
                -- Set alternating background colors
                local ROW_COLOR_EVEN = UI_LAYOUT.ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
                local ROW_COLOR_ODD = UI_LAYOUT.ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}
                local bgColor = (animIdx % 2 == 0) and ROW_COLOR_EVEN or ROW_COLOR_ODD
                
                if not row.bg then
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                end
                row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
                
                -- Update quantity
                row.qtyText:SetText(format("|cffffff00%s|r", FormatNumber(item.stackCount or 1)))
                
                -- Update icon
                row.icon:SetTexture(item.iconFileID or 134400)
                
                -- Update name (with pet cage handling)
                local nameWidth = width - 200
                row.nameText:SetWidth(nameWidth)
                local baseName = item.name or format("Item %s", tostring(item.itemID or "?"))
                -- Use GetItemDisplayName to handle caged pets (shows pet name instead of "Pet Cage")
                local displayName = WarbandNexus:GetItemDisplayName(item.itemID, baseName, item.classID)
                row.nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality), displayName))
                
                -- Update location
                local locText = ""
                if currentItemsSubTab == "warband" then
                    locText = item.tabIndex and format("Tab %d", item.tabIndex) or ""
                else
                    -- Personal Items: distinguish between Bank and Inventory
                    if item.actualBagID then
                        if item.actualBagID == -1 then
                            locText = "Bank"
                        elseif item.actualBagID >= 0 and item.actualBagID <= 5 then
                            locText = format("Bag %d", item.actualBagID)
                        else
                            locText = format("Bank Bag %d", item.actualBagID - 5)
                        end
                    end
                end
                row.locationText:SetText(locText)
                row.locationText:SetTextColor(1, 1, 1)  -- White
                
                -- Update hover/tooltip handlers (custom tooltip with ItemID)
                row:SetScript("OnEnter", function(self)
                    if not ShowTooltip then
                        return
                    end
                    
                    -- Build tooltip lines
                    local lines = {}
                    
                    -- Item ID
                    table.insert(lines, {text = "Item ID: " .. tostring(item.itemID or "Unknown"), color = {0.4, 0.8, 1}})
                    
                    -- Quality info
                    if item.quality then
                        local qualityNames = {"Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom"}
                        local qualityName = qualityNames[item.quality + 1] or "Unknown"
                        local qualityColor = ITEM_QUALITY_COLORS[item.quality]
                        if qualityColor then
                            table.insert(lines, {text = "Quality: " .. qualityName, color = {qualityColor.r, qualityColor.g, qualityColor.b}})
                        end
                    end
                    
                    -- Stack count
                    if item.stackCount and item.stackCount > 1 then
                        table.insert(lines, {text = "Stack: " .. FormatNumber(item.stackCount), color = {1, 1, 1}})
                    end
                    
                    -- Location
                    if item.location then
                        table.insert(lines, {text = "Location: " .. item.location, color = {0.7, 0.7, 0.7}})
                    end
                    
                    table.insert(lines, {type = "spacer"})
                    
                    -- Instructions
                    if WarbandNexus.bankIsOpen then
                        table.insert(lines, {text = "|cff00ff00Right-Click|r Move to bag", color = {1, 1, 1}})
                        if item.stackCount and item.stackCount > 1 then
                            table.insert(lines, {text = "|cff00ff00Shift+Right-Click|r Split stack", color = {1, 1, 1}})
                        end
                        table.insert(lines, {text = "|cff888888Left-Click|r Pick up", color = {0.7, 0.7, 0.7}})
                    else
                        table.insert(lines, {text = "|cffff6600Bank not open|r", color = {1, 1, 1}})
                    end
                    table.insert(lines, {text = "|cff888888Shift+Left-Click|r Link in chat", color = {0.7, 0.7, 0.7}})
                    
                    -- Show custom tooltip
                    ShowTooltip(self, {
                        type = "custom",
                        title = item.name or "Item",
                        lines = lines,
                        anchor = "ANCHOR_LEFT"
                    })
                end)
                row:SetScript("OnLeave", function(self)
                    if HideTooltip then
                        HideTooltip()
                    end
                end)
                
                -- Click handlers for item interaction (read-only: chat link only)
                row:SetScript("OnMouseUp", function(self, button)
                    -- Shift+Left-click: Link item in chat (safe, non-protected function)
                    if button == "LeftButton" and IsShiftKeyDown() and item.itemLink then
                        ChatEdit_InsertLink(item.itemLink)
                        return
                    end
                    
                    -- All other clicks: No action (read-only mode)
                    -- Item manipulation has been removed to prevent taint
                end)
                
                yOffset = yOffset + ROW_SPACING
            end  -- for item in group.items
        end  -- if group.expanded
        
        -- Add spacing after each group section
        yOffset = yOffset + SECTION_SPACING
    end  -- for typeName in groupOrder
    
    return yOffset + UI_LAYOUT.minBottomSpacing
end -- DrawItemsResults

