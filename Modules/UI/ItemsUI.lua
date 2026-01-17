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

-- Import shared UI layout constants
local UI_LAYOUT = ns.UI_LAYOUT
local ROW_HEIGHT = UI_LAYOUT.ROW_HEIGHT
local ROW_SPACING = UI_LAYOUT.ROW_SPACING
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING

-- Performance: Local function references
local format = string.format
local date = date

-- Module-level state (shared with main UI.lua via namespace)
-- These are accessed via ns.UI_GetItemsSubTab(), ns.UI_GetItemsSearchText(), etc.

--============================================================================
-- DRAW ITEM LIST (Main Items Tab)
--============================================================================

function WarbandNexus:DrawItemList(parent)
    local yOffset = 0 -- No top padding when search bar is present
    local width = parent:GetWidth() - 20 -- Match header padding (10 left + 10 right)
    
    -- PERFORMANCE: Release pooled frames back to pool before redrawing
    ReleaseAllPooledChildren(parent)
    
    -- ===== HEADER CARD (Always shown) =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_36")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Bank Items|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Browse and manage your Warband and Personal bank")
    
    -- Module Enable/Disable Checkbox
    local enableCheckbox = CreateFrame("CheckButton", nil, titleCard, "UICheckButtonTemplate")
    enableCheckbox:SetSize(24, 24)
    enableCheckbox:SetPoint("RIGHT", titleCard, "RIGHT", -15, 0)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.items ~= false
    enableCheckbox:SetChecked(moduleEnabled)
    
    local checkboxLabel = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkboxLabel:SetPoint("RIGHT", enableCheckbox, "LEFT", -5, 0)
    checkboxLabel:SetText("Enable")
    checkboxLabel:SetTextColor(1, 1, 1)
    
    enableCheckbox:SetScript("OnClick", function(checkbox)
        local enabled = checkbox:GetChecked()
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
    end)
    
    yOffset = yOffset + 75
    
    -- Check if module is disabled - show message below header
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.items then
        local disabledText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        disabledText:SetPoint("TOP", parent, "TOP", 0, -yOffset - 50)
        disabledText:SetText("|cff888888Module disabled. Check the box above to enable.|r")
        return yOffset + 100
    end
    
    -- CRITICAL: Sync WoW bank tab whenever we draw the item list
    -- This ensures right-click deposits go to the correct bank
    if self.bankIsOpen then
        self:SyncBankTab()
    end
    
    -- Get state from namespace (managed by main UI.lua)
    local currentItemsSubTab = ns.UI_GetItemsSubTab()
    local itemsSearchText = ns.UI_GetItemsSearchText()
    local expandedGroups = ns.UI_GetExpandedGroups()
    
    -- ===== SUB-TAB BUTTONS =====
    local tabFrame = CreateFrame("Frame", nil, parent)
    tabFrame:SetSize(width, 32)
    tabFrame:SetPoint("TOPLEFT", 8, -yOffset)
    
    -- Get theme colors
    local COLORS = GetCOLORS()
    local tabActiveColor = COLORS.tabActive
    local tabInactiveColor = COLORS.tabInactive
    local accentColor = COLORS.accent
    
    -- PERSONAL BANK BUTTON (First/Left)
    local personalBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
    personalBtn:SetSize(130, 28)
    personalBtn:SetPoint("LEFT", 0, 0)
    
    -- Add backdrop for border
    personalBtn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    
    local isPersonalActive = currentItemsSubTab == "personal"
    personalBtn:SetBackdropColor(
        isPersonalActive and tabActiveColor[1] or tabInactiveColor[1],
        isPersonalActive and tabActiveColor[2] or tabInactiveColor[2],
        isPersonalActive and tabActiveColor[3] or tabInactiveColor[3],
        1
    )
    -- Set border color (always use accent color, vary opacity)
    if isPersonalActive then
        personalBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
    else
        personalBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
    end
    
    -- Remove old texture background (now using backdrop)
    local personalBg = personalBtn  -- Keep reference name for compatibility
    
    local personalText = personalBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    personalText:SetPoint("CENTER")
    personalText:SetText("Personal Bank")
    personalText:SetTextColor(1, 1, 1)  -- Fixed white color
    
    personalBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("personal")  -- This now automatically calls SyncBankTab
        WarbandNexus:RefreshUI()
    end)
    personalBtn:SetScript("OnEnter", function(self)
        local hoverR = accentColor[1] * 0.6 + 0.15
        local hoverG = accentColor[2] * 0.6 + 0.15
        local hoverB = accentColor[3] * 0.6 + 0.15
        self:SetBackdropColor(hoverR, hoverG, hoverB, 1)
        self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
    end)
    personalBtn:SetScript("OnLeave", function(self)
        local active = ns.UI_GetItemsSubTab() == "personal"
        local c = active and tabActiveColor or tabInactiveColor
        self:SetBackdropColor(c[1], c[2], c[3], 1)
        if active then
            self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
        else
            self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
        end
    end)
    
    -- WARBAND BANK BUTTON (Second/Right)
    local warbandBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
    warbandBtn:SetSize(130, 28)
    warbandBtn:SetPoint("LEFT", personalBtn, "RIGHT", 8, 0)
    
    -- Add backdrop for border
    warbandBtn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    
    local isWarbandActive = currentItemsSubTab == "warband"
    warbandBtn:SetBackdropColor(
        isWarbandActive and tabActiveColor[1] or tabInactiveColor[1],
        isWarbandActive and tabActiveColor[2] or tabInactiveColor[2],
        isWarbandActive and tabActiveColor[3] or tabInactiveColor[3],
        1
    )
    -- Set border color (always use accent color, vary opacity)
    if isWarbandActive then
        warbandBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
    else
        warbandBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
    end
    
    -- Remove old texture background (now using backdrop)
    local warbandBg = warbandBtn  -- Keep reference name for compatibility
    
    local warbandText = warbandBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warbandText:SetPoint("CENTER")
    warbandText:SetText("Warband Bank")
    warbandText:SetTextColor(1, 1, 1)  -- Fixed white color
    
    warbandBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("warband")  -- This now automatically calls SyncBankTab
        WarbandNexus:RefreshUI()
    end)
    warbandBtn:SetScript("OnEnter", function(self)
        local hoverR = accentColor[1] * 0.6 + 0.15
        local hoverG = accentColor[2] * 0.6 + 0.15
        local hoverB = accentColor[3] * 0.6 + 0.15
        self:SetBackdropColor(hoverR, hoverG, hoverB, 1)
        self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
    end)
    warbandBtn:SetScript("OnLeave", function(self) 
        local active = ns.UI_GetItemsSubTab() == "warband"
        local c = active and tabActiveColor or tabInactiveColor
        self:SetBackdropColor(c[1], c[2], c[3], 1)
        if active then
            self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
        else
            self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
        end
    end)
    
    -- GUILD BANK BUTTON (Third/Right) - DISABLED BY DEFAULT
    if ENABLE_GUILD_BANK then
        local guildBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
        guildBtn:SetSize(130, 28)
        guildBtn:SetPoint("LEFT", warbandBtn, "RIGHT", 8, 0)
        
        -- Add backdrop for border
        guildBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        
        local isGuildActive = currentItemsSubTab == "guild"
        guildBtn:SetBackdropColor(
            isGuildActive and tabActiveColor[1] or tabInactiveColor[1],
            isGuildActive and tabActiveColor[2] or tabInactiveColor[2],
            isGuildActive and tabActiveColor[3] or tabInactiveColor[3],
            1
        )
        -- Set border color (always use accent color, vary opacity)
        if isGuildActive then
            guildBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
        else
            guildBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
        end
        
        -- Remove old texture background (now using backdrop)
        local guildBg = guildBtn  -- Keep reference name for compatibility
        
        local guildText = guildBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        guildText:SetPoint("CENTER")
        guildText:SetText("Guild Bank")
        guildText:SetTextColor(1, 1, 1)  -- Fixed white color
        
        -- Check if player is in a guild
        local isInGuild = IsInGuild()
        if not isInGuild then
            guildBtn:Disable()
            guildBtn:SetAlpha(0.5)
            guildText:SetTextColor(0.4, 0.4, 0.4)  -- Dim gray when disabled
        end
        
        guildBtn:SetScript("OnClick", function()
            if not isInGuild then
                WarbandNexus:Print("|cffff6600You must be in a guild to access Guild Bank.|r")
                return
            end
            ns.UI_SetItemsSubTab("guild")  -- This now automatically calls SyncBankTab
            WarbandNexus:RefreshUI()
        end)
        guildBtn:SetScript("OnEnter", function(self) 
            if isInGuild then
                local hoverR = accentColor[1] * 0.6 + 0.15
                local hoverG = accentColor[2] * 0.6 + 0.15
                local hoverB = accentColor[3] * 0.6 + 0.15
                self:SetBackdropColor(hoverR, hoverG, hoverB, 1)
                self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
            end
        end)
        guildBtn:SetScript("OnLeave", function(self) 
            local active = ns.UI_GetItemsSubTab() == "guild"
            local c = active and tabActiveColor or tabInactiveColor
            self:SetBackdropColor(c[1], c[2], c[3], 1)
            if active then
                self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
            else
                self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
            end
        end)
    end -- ENABLE_GUILD_BANK
    
    -- ===== GOLD CONTROLS (Warband Bank ONLY) =====
    if currentItemsSubTab == "warband" then
        -- Gold display for Warband Bank
        local goldDisplay = tabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        goldDisplay:SetPoint("RIGHT", tabFrame, "RIGHT", -10, 0)
        local warbandGold = WarbandNexus:GetWarbandBankMoney() or 0
        goldDisplay:SetText(GetCoinTextureString(warbandGold))
    end
    -- Personal Bank has no gold controls (WoW doesn't support gold storage in personal bank)
    
    yOffset = yOffset + 40
    
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
    
    -- ===== STATS BAR =====
    local statsBar = CreateFrame("Frame", nil, parent)
    statsBar:SetSize(width, 24)
    statsBar:SetPoint("TOPLEFT", 8, -yOffset)
    
    local statsBg = statsBar:CreateTexture(nil, "BACKGROUND")
    statsBg:SetAllPoints()
    statsBg:SetColorTexture(0.08, 0.08, 0.10, 1)
    
    local statsText = statsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsText:SetPoint("LEFT", 10, 0)
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
    statsText:SetTextColor(0.6, 0.6, 0.6)
    
    yOffset = yOffset + 28
    
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
        local isExpanded = expandedGroups[group.groupKey]
        
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
            else
                expandedGroups[key] = not expandedGroups[key]
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
        groupHeader:SetPoint("TOPLEFT", 10, -yOffset)
        
        yOffset = yOffset + HEADER_SPACING
        
        -- Draw items in this group (if expanded)
        if isExpanded then
            for _, item in ipairs(group.items) do
                rowIdx = rowIdx + 1
                local i = rowIdx
                
                -- PERFORMANCE: Acquire from pool instead of creating new
                local row = AcquireItemRow(parent, width, ROW_HEIGHT)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 8, -yOffset)
                row.idx = i
                
                -- Update background color (alternating rows)
                row.bg:SetColorTexture(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                
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
                row.locationText:SetTextColor(0.5, 0.5, 0.5)
                
                -- Update hover/tooltip handlers
                row:SetScript("OnEnter", function(self)
                    self.bg:SetColorTexture(0.15, 0.15, 0.20, 1)
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
                    self.bg:SetColorTexture(self.idx % 2 == 0 and 0.07 or 0.05, self.idx % 2 == 0 and 0.07 or 0.05, self.idx % 2 == 0 and 0.09 or 0.06, 1)
                    GameTooltip:Hide()
                end)
                
                -- Helper to get bag/slot IDs
                local function GetItemBagSlot()
                    local bagID, slotID
                    
                    if currentItemsSubTab == "warband" and item.tabIndex then
                        local warbandBags = {
                            Enum.BagIndex.AccountBankTab_1,
                            Enum.BagIndex.AccountBankTab_2,
                            Enum.BagIndex.AccountBankTab_3,
                            Enum.BagIndex.AccountBankTab_4,
                            Enum.BagIndex.AccountBankTab_5,
                        }
                        bagID = warbandBags[item.tabIndex]
                        slotID = item.slotID
                    elseif currentItemsSubTab == "personal" and item.bagIndex then
                        -- Use stored bagID from item data if available
                        if item.actualBagID then
                            bagID = item.actualBagID
                        else
                            -- Use enum-based lookup
                            local personalBags = { 
                                Enum.BagIndex.Bank or -1, 
                                Enum.BagIndex.BankBag_1 or 6, 
                                Enum.BagIndex.BankBag_2 or 7, 
                                Enum.BagIndex.BankBag_3 or 8, 
                                Enum.BagIndex.BankBag_4 or 9, 
                                Enum.BagIndex.BankBag_5 or 10, 
                                Enum.BagIndex.BankBag_6 or 11, 
                                Enum.BagIndex.BankBag_7 or 12 
                            }
                            bagID = personalBags[item.bagIndex]
                        end
                        slotID = item.slotID
                    end
                    return bagID, slotID
                end
                
                -- Click handlers for item interaction
                row:SetScript("OnMouseUp", function(self, button)
                    local bagID, slotID = GetItemBagSlot()
                    
                    
                    -- Bank must be open to interact with items
                    local canInteract = WarbandNexus.bankIsOpen
                    
                    -- Left-click: Pick up item or link in chat
                    if button == "LeftButton" then
                        if IsShiftKeyDown() and item.itemLink then
                            ChatEdit_InsertLink(item.itemLink)
                            return
                        end
                        
                        if canInteract and bagID and slotID then
                            -- Combat check before pickup
                            if InCombatLockdown() then
                                WarbandNexus:Print("|cffff6600Cannot move items during combat.|r")
                                return
                            end
                            
                            -- Use API wrapper (TWW compatible)
                            local success = WarbandNexus:API_PickupItem(bagID, slotID)
                            if not success then
                                return -- Already showed error message
                            end
                        else
                            WarbandNexus:Print("|cffff6600Bank must be open to move items.|r")
                        end
                    
                    -- Right-click: Move item to bag (context-aware)
                    elseif button == "RightButton" then
                        -- Check if appropriate bank is open based on current tab
                        local canInteract = false
                        local bankType = currentItemsSubTab
                        
                        if bankType == "personal" or bankType == "warband" then
                            canInteract = WarbandNexus.bankIsOpen
                        elseif bankType == "guild" then
                            if ENABLE_GUILD_BANK then
                                canInteract = WarbandNexus.guildBankIsOpen
                            else
                                WarbandNexus:Print("|cffff6600Guild Bank feature is currently disabled.|r")
                                return
                            end
                        end
                        
                        if not canInteract then
                            if bankType == "guild" then
                                WarbandNexus:Print("|cffff6600Guild Bank must be open to move items.|r")
                            else
                                WarbandNexus:Print("|cffff6600Bank must be open to move items.|r")
                            end
                            return
                        end
                        
                        if not bagID or not slotID then return end
                        
                        -- Combat check before any item interaction
                        if InCombatLockdown() then
                            WarbandNexus:Print("|cffff6600Cannot move items during combat.|r")
                            return
                        end
                        
                        -- Shift+Right-click: Split stack
                        if IsShiftKeyDown() and item.stackCount and item.stackCount > 1 then
                            -- Use API wrapper (TWW compatible)
                            local success = WarbandNexus:API_PickupItem(bagID, slotID)
                            if not success then
                                return -- Already showed error message
                            end
                            if OpenStackSplitFrame then
                                OpenStackSplitFrame(item.stackCount, self, "BOTTOMLEFT", "TOPLEFT")
                            end
                        else
                            -- Normal right-click: Move entire stack to bag
                            -- Use API wrapper (TWW compatible)
                            local success = WarbandNexus:API_PickupItem(bagID, slotID)
                            if not success then
                                return -- Already showed error message
                            end
                            
                            local cursorType, cursorItemID = GetCursorInfo()
                            
                            if cursorType == "item" then
                                -- Find a free slot in player bags
                                local placed = false
                                
                                for destBag = 0, 4 do
                                    -- Use API wrappers (TWW compatible)
                                    local numSlots = WarbandNexus:API_GetBagSize(destBag)
                                    local freeSlots = WarbandNexus:API_GetFreeBagSlots(destBag)
                                    
                                    if freeSlots > 0 then
                                        -- Find the actual empty slot
                                        for destSlot = 1, numSlots do
                                            local slotInfo = WarbandNexus:API_GetContainerItemInfo(destBag, destSlot)
                                            if not slotInfo then
                                                WarbandNexus:API_PickupItem(destBag, destSlot)
                                                placed = true
                                                break
                                            end
                                        end
                                        if placed then break end
                                    end
                                end
                                
                                if not placed then
                                    ClearCursor()
                                    WarbandNexus:Print("|cffff6600No free bag space!|r")
                                end
                            end
                            
                            -- Fast re-scan and refresh UI
                            C_Timer.After(0.1, function()
                                if not WarbandNexus then return end
                                
                                -- Re-scan the appropriate bank
                                if currentItemsSubTab == "warband" then
                                    if WarbandNexus.ScanWarbandBank then
                                        WarbandNexus:ScanWarbandBank()
                                    end
                                else
                                    if WarbandNexus.ScanPersonalBank then
                                        WarbandNexus:ScanPersonalBank()
                                    end
                                end
                                
                                -- Then refresh UI
                                if WarbandNexus.RefreshUI then
                                    WarbandNexus:RefreshUI()
                                end
                            end)
                        end
                    end
                end)
                
                yOffset = yOffset + ROW_SPACING
            end  -- for item in group.items
        end  -- if group.expanded
    end  -- for typeName in groupOrder
    
    return yOffset + 20
end

