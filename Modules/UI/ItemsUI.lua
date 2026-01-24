--[[
    Warband Nexus - Items Tab
    Display and manage Warband and Personal bank items with interactive controls
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Feature Flags
local ENABLE_GUILD_BANK = false -- Set to true when ready to enable Guild Bank features

-- Import shared UI components (always get fresh reference)
local function GetCOLORS()
    return ns.UI_COLORS
end
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
local ApplyHoverEffect = ns.UI_ApplyHoverEffect
local UpdateBorderColor = ns.UI_UpdateBorderColor

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
-- These are accessed via ns.UI_GetItemsSubTab(), ns.UI_GetItemsSearchText(), etc.

--============================================================================
-- DRAW ITEM LIST (Main Items Tab)
--============================================================================

function WarbandNexus:DrawItemList(parent)
    self.recentlyExpanded = self.recentlyExpanded or {}
    local yOffset = 8 -- Top padding for consistency with other tabs
    local width = parent:GetWidth() - 20 -- Match header padding (10 left + 10 right)
    
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
    
    -- Module Enable/Disable Checkbox
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.items ~= false
    local enableCheckbox = CreateThemedCheckbox(titleCard, moduleEnabled)
    enableCheckbox:SetPoint("LEFT", headerIcon.border, "RIGHT", 8, 0)
    
    enableCheckbox:SetScript("OnClick", function(checkbox)
        local enabled = checkbox:GetChecked()
        -- Use ModuleManager for proper event handling
        if self.SetItemsModuleEnabled then
            self:SetItemsModuleEnabled(enabled)
            if enabled then
                -- Rescan if bank is open
                if self.bankIsOpen then
                    if self.ScanWarbandBank then self:ScanWarbandBank() end
                    if self.ScanPersonalBank then self:ScanPersonalBank() end
                end
            end
        else
            -- Fallback
            self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
            self.db.profile.modulesEnabled.items = enabled
            if enabled then
                -- Rescan if bank is open
                if self.bankIsOpen then
                    if self.ScanWarbandBank then self:ScanWarbandBank() end
                    if self.ScanPersonalBank then self:ScanPersonalBank() end
                end
            end
            if self.RefreshUI then self:RefreshUI() end
        end
    end)
    
    enableCheckbox:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Items Module is " .. (btn:GetChecked() and "Enabled" or "Disabled"))
        GameTooltip:AddLine("Click to " .. (btn:GetChecked() and "disable" or "enable"), 1, 1, 1)
        GameTooltip:Show()
    end)
    
    enableCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", enableCheckbox, "RIGHT", 12, 5)
    titleText:SetText("|cff" .. hexColor .. "Bank Items|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", enableCheckbox, "RIGHT", 12, -12)
    subtitleText:SetTextColor(1, 1, 1)  -- White
    subtitleText:SetText("Browse and manage your Warband and Personal bank")
    
    yOffset = yOffset + UI_LAYOUT.afterHeader  -- Standard spacing after title card
    
    -- Check if module is disabled - show message below header
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.items then
        local disabledText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        disabledText:SetPoint("TOP", parent, "TOP", 0, -yOffset - 50)
        disabledText:SetText("|cff888888Module disabled. Check the box above to enable.|r")
        return yOffset + UI_LAYOUT.emptyStateSpacing
    end
    
    -- Get state from namespace (managed by main UI.lua)
    local currentItemsSubTab = ns.UI_GetItemsSubTab()
    local itemsSearchText = ns.UI_GetItemsSearchText()
    local expandedGroups = ns.UI_GetExpandedGroups()
    
    -- ===== SUB-TAB BUTTONS =====
    local tabFrame = CreateFrame("Frame", nil, parent)
    tabFrame:SetHeight(32)
    tabFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    tabFrame:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Get theme colors
    local COLORS = GetCOLORS()
    local tabActiveColor = COLORS.tabActive
    local tabInactiveColor = COLORS.tabInactive
    local accentColor = COLORS.accent
    
    -- PERSONAL BANK BUTTON (First/Left)
    local personalBtn = CreateFrame("Button", nil, tabFrame)
    personalBtn:SetSize(130, 28)
    personalBtn:SetPoint("LEFT", 0, 0)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(personalBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    -- Apply hover effect
    if ApplyHoverEffect then
        ApplyHoverEffect(personalBtn, 0.25)
    end
    
    local personalText = personalBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    personalText:SetPoint("CENTER")
    personalText:SetText("Personal Bank")
    personalText:SetTextColor(1, 1, 1)  -- Fixed white color
    
    personalBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("personal")  -- Switch to Personal Bank tab
        WarbandNexus:RefreshUI()
    end)
    
    -- WARBAND BANK BUTTON (Second/Right)
    local warbandBtn = CreateFrame("Button", nil, tabFrame)
    warbandBtn:SetSize(130, 28)
    warbandBtn:SetPoint("LEFT", personalBtn, "RIGHT", 8, 0)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(warbandBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    -- Apply hover effect
    if ApplyHoverEffect then
        ApplyHoverEffect(warbandBtn, 0.25)
    end
    
    local warbandText = warbandBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warbandText:SetPoint("CENTER")
    warbandText:SetText("Warband Bank")
    warbandText:SetTextColor(1, 1, 1)  -- Fixed white color
    
    warbandBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("warband")  -- Switch to Warband Bank tab
        WarbandNexus:RefreshUI()
    end)
    
    -- GUILD BANK BUTTON (Third/Right) - DISABLED BY DEFAULT
    if ENABLE_GUILD_BANK then
        local guildBtn = CreateFrame("Button", nil, tabFrame)
        guildBtn:SetSize(130, 28)
        guildBtn:SetPoint("LEFT", warbandBtn, "RIGHT", 8, 0)
        
        -- No backdrop (naked frame)
        
        local guildText = guildBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
        local goldDisplay = tabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        goldDisplay:SetPoint("RIGHT", tabFrame, "RIGHT", -10, 0)
        local warbandGold = WarbandNexus:GetWarbandBankMoney() or 0
        goldDisplay:SetText(WarbandNexus:API_FormatMoney(warbandGold))
    end
    -- Personal Bank has no gold controls (WoW doesn't support gold storage in personal bank)
    
    yOffset = yOffset + 32 + UI_LAYOUT.afterElement  -- Tab frame height + spacing
    
    -- ===== SEARCH BOX (Below sub-tabs) =====
    local CreateSearchBox = ns.UI_CreateSearchBox
    local itemsSearchText = ns.itemsSearchText or ""
    
    local searchBox = CreateSearchBox(parent, width, "Search items...", function(text)
        ns.itemsSearchText = text
        
        -- Clear only results container
        local resultsContainer = parent.resultsContainer
        if resultsContainer then
            local children = {resultsContainer:GetChildren()}
            for _, child in ipairs(children) do
                child:Hide()
                child:SetParent(nil)
            end
            
            -- Redraw only results
            WarbandNexus:DrawItemsResults(resultsContainer, 0, width, ns.UI_GetItemsSubTab(), text)
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
        local wb = bankStats.warband
        statsText:SetText(string.format("|cffa335ee%d items|r  •  %d/%d slots  •  Last: %s",
            #items, wb.usedSlots, wb.totalSlots,
            wb.lastScan > 0 and date("%H:%M", wb.lastScan) or "Never"))
    elseif currentItemsSubTab == "guild" then
        local gb = bankStats.guild or { usedSlots = 0, totalSlots = 0, lastScan = 0 }
        statsText:SetText(string.format("|cff00ff00%d items|r  •  %d/%d slots  •  Last: %s",
            #items, gb.usedSlots, gb.totalSlots,
            gb.lastScan > 0 and date("%H:%M", gb.lastScan) or "Never"))
    else
        local pb = bankStats.personal
        statsText:SetText(string.format("|cff88ff88%d items|r  •  %d/%d slots  •  Last: %s",
            #items, pb.usedSlots, pb.totalSlots,
            pb.lastScan > 0 and date("%H:%M", pb.lastScan) or "Never"))
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
        return DrawEmptyState(self, parent, yOffset, itemsSearchText ~= "", itemsSearchText)
    end
    
    -- ===== GROUP ITEMS BY TYPE =====
    local groups = {}
    local groupOrder = {}
    
    for _, item in ipairs(items) do
        local typeName = item.itemType or "Miscellaneous"
        if not groups[typeName] then
            -- Use persisted expanded state, default to true (expanded)
            local groupKey = currentItemsSubTab .. "_" .. typeName
            if expandedGroups[groupKey] == nil then
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
            format("%s (%d)", typeName, #group.items),
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
                row.qtyText:SetText(format("|cffffff00%d|r", item.stackCount or 1))
                
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
                local locText
                if currentItemsSubTab == "warband" then
                    locText = item.tabIndex and format("Tab %d", item.tabIndex) or ""
                else
                    locText = item.bagIndex and format("Bag %d", item.bagIndex) or ""
                end
                row.locationText:SetText(locText)
                row.locationText:SetTextColor(1, 1, 1)  -- White
                
                -- Update hover/tooltip handlers
                row:SetScript("OnEnter", function(self)
                    if item.itemLink then
                        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                        GameTooltip:SetHyperlink(item.itemLink)
                        GameTooltip:AddLine(" ")
                        
                        if WarbandNexus.bankIsOpen then
                            GameTooltip:AddLine("|cff00ff00Right-Click|r Move to bag", 1, 1, 1)
                            if item.stackCount and item.stackCount > 1 then
                                GameTooltip:AddLine("|cff00ff00Shift+Right-Click|r Split stack", 1, 1, 1)
                            end
                            GameTooltip:AddLine("|cff888888Left-Click|r Pick up", 0.7, 0.7, 0.7)
                        else
                            GameTooltip:AddLine("|cffff6600Bank not open|r", 1, 1, 1)
                        end
                        GameTooltip:AddLine("|cff888888Shift+Left-Click|r Link in chat", 0.7, 0.7, 0.7)
                        GameTooltip:Show()
                    elseif item.itemID then
                        -- Fallback: Use itemID if itemLink is not available
                        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                        GameTooltip:SetItemByID(item.itemID)
                        GameTooltip:AddLine(" ")
                        
                        if WarbandNexus.bankIsOpen then
                            GameTooltip:AddLine("|cff00ff00Right-Click|r Move to bag", 1, 1, 1)
                            if item.stackCount and item.stackCount > 1 then
                                GameTooltip:AddLine("|cff00ff00Shift+Right-Click|r Split stack", 1, 1, 1)
                            end
                            GameTooltip:AddLine("|cff888888Left-Click|r Pick up", 0.7, 0.7, 0.7)
                        else
                            GameTooltip:AddLine("|cffff6600Bank not open|r", 1, 1, 1)
                        end
                        GameTooltip:AddLine("|cff888888Shift+Left-Click|r Link in chat", 0.7, 0.7, 0.7)
                        GameTooltip:Show()
                    end
                end)
                row:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
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

