--[[
    Warband Nexus - Items Tab
    Display and manage Warband and Personal bank items with interactive controls
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local COLORS = ns.UI_COLORS
local GetQualityHex = ns.UI_GetQualityHex
local CreateCard = ns.UI_CreateCard
local DrawEmptyState = ns.UI_DrawEmptyState
local AcquireItemRow = ns.UI_AcquireItemRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Performance: Local function references
local format = string.format
local date = date

-- Constants
local ROW_HEIGHT = 26

-- Module-level state (shared with main UI.lua via namespace)
-- These are accessed via ns.UI_GetItemsSubTab(), ns.UI_GetItemsSearchText(), etc.

--============================================================================
-- DRAW ITEM LIST (Main Items Tab)
--============================================================================

function WarbandNexus:DrawItemList(parent)
    local yOffset = 10
    local width = parent:GetWidth() - 16
    
    -- PERFORMANCE: Release pooled frames back to pool before redrawing
    ReleaseAllPooledChildren(parent)
    
    -- CRITICAL: Sync WoW bank tab whenever we draw the item list
    -- This ensures right-click deposits go to the correct bank
    if self.bankIsOpen then
        self:SyncBankTab()
    end
    
    -- Get state from namespace (managed by main UI.lua)
    local currentItemsSubTab = ns.UI_GetItemsSubTab()
    local itemsSearchText = ns.UI_GetItemsSearchText()
    local expandedGroups = ns.UI_GetExpandedGroups()
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_36")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    titleText:SetText("|cffa335eeBank Items|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Browse and manage your Warband and Personal bank")
    
    yOffset = yOffset + 80
    
    -- ===== SUB-TAB BUTTONS =====
    local tabFrame = CreateFrame("Frame", nil, parent)
    tabFrame:SetSize(width, 32)
    tabFrame:SetPoint("TOPLEFT", 8, -yOffset)
    
    -- PERSONAL BANK BUTTON (First/Left)
    local personalBtn = CreateFrame("Button", nil, tabFrame)
    personalBtn:SetSize(130, 28)
    personalBtn:SetPoint("LEFT", 0, 0)
    
    local personalBg = personalBtn:CreateTexture(nil, "BACKGROUND")
    personalBg:SetAllPoints()
    local isPersonalActive = currentItemsSubTab == "personal"
    personalBg:SetColorTexture(isPersonalActive and 0.20 or 0.08, isPersonalActive and 0.12 or 0.08, isPersonalActive and 0.30 or 0.10, 1)
    
    local personalText = personalBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    personalText:SetPoint("CENTER")
    personalText:SetText(isPersonalActive and "|cff88ff88Personal Bank|r" or "|cff888888Personal Bank|r")
    
    personalBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("personal")  -- This now automatically calls SyncBankTab
        WarbandNexus:RefreshUI()
    end)
    personalBtn:SetScript("OnEnter", function(self) personalBg:SetColorTexture(0.25, 0.15, 0.35, 1) end)
    personalBtn:SetScript("OnLeave", function(self)
        local active = ns.UI_GetItemsSubTab() == "personal"
        personalBg:SetColorTexture(active and 0.20 or 0.08, active and 0.12 or 0.08, active and 0.30 or 0.10, 1)
    end)
    
    -- WARBAND BANK BUTTON (Second/Right)
    local warbandBtn = CreateFrame("Button", nil, tabFrame)
    warbandBtn:SetSize(130, 28)
    warbandBtn:SetPoint("LEFT", personalBtn, "RIGHT", 8, 0)
    
    local warbandBg = warbandBtn:CreateTexture(nil, "BACKGROUND")
    warbandBg:SetAllPoints()
    local isWarbandActive = currentItemsSubTab == "warband"
    warbandBg:SetColorTexture(isWarbandActive and 0.20 or 0.08, isWarbandActive and 0.12 or 0.08, isWarbandActive and 0.30 or 0.10, 1)
    
    local warbandText = warbandBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warbandText:SetPoint("CENTER")
    warbandText:SetText(isWarbandActive and "|cffa335eeWarband Bank|r" or "|cff888888Warband Bank|r")
    
    warbandBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("warband")  -- This now automatically calls SyncBankTab
        WarbandNexus:RefreshUI()
    end)
    warbandBtn:SetScript("OnEnter", function(self) warbandBg:SetColorTexture(0.25, 0.15, 0.35, 1) end)
    warbandBtn:SetScript("OnLeave", function(self) 
        local active = ns.UI_GetItemsSubTab() == "warband"
        warbandBg:SetColorTexture(active and 0.20 or 0.08, active and 0.12 or 0.08, active and 0.30 or 0.10, 1)
    end)
    
    -- ===== GOLD CONTROLS (Warband Bank ONLY) =====
    if currentItemsSubTab == "warband" then
        -- Gold display for Warband Bank
        local goldDisplay = tabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        goldDisplay:SetPoint("RIGHT", tabFrame, "RIGHT", -160, 0)
        local warbandGold = WarbandNexus:GetWarbandBankMoney() or 0
        goldDisplay:SetText(GetCoinTextureString(warbandGold))
        
        -- Deposit button
        local depositBtn = CreateFrame("Button", nil, tabFrame, "UIPanelButtonTemplate")
        depositBtn:SetSize(70, 24)
        depositBtn:SetPoint("RIGHT", tabFrame, "RIGHT", -80, 0)
        depositBtn:SetText("Deposit")
        depositBtn:SetScript("OnClick", function()
            if not WarbandNexus.bankIsOpen then
                WarbandNexus:Print("|cffff6600Bank must be open to deposit gold.|r")
                return
            end
            WarbandNexus:ShowGoldTransferPopup("warband", "deposit")
        end)
        depositBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Deposit Gold", 1, 0.82, 0)
            GameTooltip:AddLine("Deposit gold to Warband Bank", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        depositBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        -- Withdraw button
        local withdrawBtn = CreateFrame("Button", nil, tabFrame, "UIPanelButtonTemplate")
        withdrawBtn:SetSize(70, 24)
        withdrawBtn:SetPoint("RIGHT", tabFrame, "RIGHT", -5, 0)
        withdrawBtn:SetText("Withdraw")
        withdrawBtn:SetScript("OnClick", function()
            if not WarbandNexus.bankIsOpen then
                WarbandNexus:Print("|cffff6600Bank must be open to withdraw gold.|r")
                return
            end
            WarbandNexus:ShowGoldTransferPopup("warband", "withdraw")
        end)
        withdrawBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Withdraw Gold", 1, 0.82, 0)
            GameTooltip:AddLine("Withdraw gold from Warband Bank", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        withdrawBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- Personal Bank has no gold controls (WoW doesn't support gold storage in personal bank)
    
    yOffset = yOffset + 40
    
    -- Get items based on selected sub-tab
    local items = {}
    if currentItemsSubTab == "warband" then
        items = self:GetWarbandBankItems() or {}
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
        
        -- Group header
        local groupHeader = CreateFrame("Button", nil, parent)
        groupHeader:SetSize(width, 24)
        groupHeader:SetPoint("TOPLEFT", 8, -yOffset)
        
        local ghBg = groupHeader:CreateTexture(nil, "BACKGROUND")
        ghBg:SetAllPoints()
        ghBg:SetColorTexture(0.12, 0.12, 0.16, 1)
        
        local ghArrow = groupHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ghArrow:SetPoint("LEFT", 8, 0)
        ghArrow:SetText(isExpanded and "-" or "+")
        ghArrow:SetTextColor(0.7, 0.7, 0.7)
        
        local ghTitle = groupHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ghTitle:SetPoint("LEFT", 22, 0)
        ghTitle:SetText(format("|cffffcc00%s|r |cff888888(%d)|r", typeName, #group.items))
        
        -- Click to expand/collapse (uses persisted state)
        local gKey = group.groupKey
        groupHeader:SetScript("OnClick", function()
            expandedGroups[gKey] = not expandedGroups[gKey]
            WarbandNexus:RefreshUI()
        end)
        groupHeader:SetScript("OnEnter", function() ghBg:SetColorTexture(0.16, 0.16, 0.22, 1) end)
        groupHeader:SetScript("OnLeave", function() ghBg:SetColorTexture(0.12, 0.12, 0.16, 1) end)
        
        yOffset = yOffset + 26
        
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
                
                -- Update name
                local nameWidth = width - 200
                row.nameText:SetWidth(nameWidth)
                local displayName = item.name or item.itemLink or format("Item %s", tostring(item.itemID or "?"))
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
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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
                    WarbandNexus:Debug("GetItemBagSlot: RESULT bagID=" .. tostring(bagID) .. ", slotID=" .. tostring(slotID))
                    return bagID, slotID
                end
                
                -- Click handlers for item interaction
                row:SetScript("OnMouseUp", function(self, button)
                    local bagID, slotID = GetItemBagSlot()
                    
                    WarbandNexus:Debug("CLICK: button=" .. tostring(button) .. ", bagID=" .. tostring(bagID) .. ", slotID=" .. tostring(slotID))
                    
                    -- Bank must be open to interact with items
                    local canInteract = WarbandNexus.bankIsOpen
                    
                    -- Left-click: Pick up item or link in chat
                    if button == "LeftButton" then
                        if IsShiftKeyDown() and item.itemLink then
                            ChatEdit_InsertLink(item.itemLink)
                            return
                        end
                        
                        if canInteract and bagID and slotID then
                            C_Container.PickupContainerItem(bagID, slotID)
                        else
                            WarbandNexus:Print("|cffff6600Bank must be open to move items.|r")
                        end
                    
                    -- Right-click: Move item to bag
                    elseif button == "RightButton" then
                        if not canInteract then
                            WarbandNexus:Print("|cffff6600Bank must be open to move items.|r")
                            return
                        end
                        
                        if not bagID or not slotID then return end
                        
                        -- Shift+Right-click: Split stack
                        if IsShiftKeyDown() and item.stackCount and item.stackCount > 1 then
                            C_Container.PickupContainerItem(bagID, slotID)
                            if OpenStackSplitFrame then
                                OpenStackSplitFrame(item.stackCount, self, "BOTTOMLEFT", "TOPLEFT")
                            end
                        else
                            -- Normal right-click: Move entire stack to bag
                            C_Container.PickupContainerItem(bagID, slotID)
                            
                            local cursorType, cursorItemID = GetCursorInfo()
                            
                            if cursorType == "item" then
                                -- Find a free slot in player bags
                                local placed = false
                                
                                for destBag = 0, 4 do
                                    local numSlots = C_Container.GetContainerNumSlots(destBag) or 0
                                    local freeSlots = C_Container.GetContainerNumFreeSlots(destBag) or 0
                                    
                                    if freeSlots > 0 then
                                        -- Find the actual empty slot
                                        for destSlot = 1, numSlots do
                                            local slotInfo = C_Container.GetContainerItemInfo(destBag, destSlot)
                                            if not slotInfo then
                                                C_Container.PickupContainerItem(destBag, destSlot)
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
                
                yOffset = yOffset + ROW_HEIGHT + 1
            end  -- for item in group.items
        end  -- if group.expanded
    end  -- for typeName in groupOrder
    
    return yOffset + 20
end

