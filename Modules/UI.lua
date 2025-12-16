--[[
    Warband Nexus - UI Module
    Handles visual interface elements using AceGUI
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- AceGUI reference
local AceGUI = LibStub("AceGUI-3.0")

-- Frame references
local mainFrame = nil
local depositQueueFrame = nil

-- Quality colors (Blizzard standard)
local QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, -- Poor (gray)
    [1] = { r = 1.00, g = 1.00, b = 1.00 }, -- Common (white)
    [2] = { r = 0.12, g = 1.00, b = 0.00 }, -- Uncommon (green)
    [3] = { r = 0.00, g = 0.44, b = 0.87 }, -- Rare (blue)
    [4] = { r = 0.64, g = 0.21, b = 0.93 }, -- Epic (purple)
    [5] = { r = 1.00, g = 0.50, b = 0.00 }, -- Legendary (orange)
    [6] = { r = 0.90, g = 0.80, b = 0.50 }, -- Artifact (gold)
    [7] = { r = 0.00, g = 0.80, b = 1.00 }, -- Heirloom (cyan)
    [8] = { r = 0.00, g = 0.80, b = 1.00 }, -- WoW Token
}

--[[
    Toggle the main window visibility (manual toggle via /wn show)
    Opens with Stats/Characters tab when showing
]]
function WarbandNexus:ToggleMainWindow()
    if mainFrame and mainFrame:IsShown() then
        mainFrame:Hide()
    else
        -- Manual toggle uses ShowMainWindow which defaults to stats tab
        self:ShowMainWindow()
    end
end

--[[
    Create and show the main window (manual open via /wn show or minimap click)
    Opens with Characters/Stats tab by default
]]
function WarbandNexus:ShowMainWindow()
    self:Debug("ShowMainWindow called (manual open)")
    
    -- Create frame if it doesn't exist
    if not mainFrame then
        mainFrame = self:CreateMainWindow()
        self:Debug("Created new mainFrame")
    end
    
    -- Manual open always defaults to stats/characters tab
    -- This is different from bank-triggered opens
    local targetTab = "stats"
    mainFrame.currentTabGroup = targetTab
    
    self:Debug(string.format("ShowMainWindow (manual): selecting tab %s", targetTab))
    
    -- Select the stats tab
    if mainFrame.tabGroup then
        mainFrame.tabGroup:SelectTab(targetTab)
    end
    
    mainFrame:Show()
end

--[[
    Create the main window frame
    @return AceGUI.Frame The main window frame
]]
function WarbandNexus:CreateMainWindow()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle(L["MAIN_WINDOW_TITLE"])
    frame:SetStatusText(L["ADDON_NAME"] .. " v" .. GetAddOnMetadata(ADDON_NAME, "Version"))
    frame:SetLayout("Flow")
    frame:SetWidth(700)
    frame:SetHeight(500)
    frame:EnableResize(true)
    
    -- Set close callback
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
    end)
    
    -- Top toolbar group
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetFullWidth(true)
    toolbar:SetHeight(40)
    toolbar:SetLayout("Flow")
    frame:AddChild(toolbar)
    
    -- Search box
    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("")
    searchBox:SetWidth(200)
    searchBox:SetText("")
    searchBox:SetCallback("OnEnterPressed", function(widget, event, text)
        self:FilterMainWindowItems(text)
    end)
    searchBox:SetCallback("OnTextChanged", function(widget, event, text)
        -- Debounced search
        if self.searchTimer then
            self:CancelTimer(self.searchTimer)
        end
        self.searchTimer = self:ScheduleTimer(function()
            self:FilterMainWindowItems(text)
        end, 0.3)
    end)
    toolbar:AddChild(searchBox)
    frame.searchBox = searchBox
    
    -- Scan button
    local scanBtn = AceGUI:Create("Button")
    scanBtn:SetText(L["BTN_SCAN"])
    scanBtn:SetWidth(100)
    scanBtn:SetCallback("OnClick", function()
        self:ScanWarbandBank()
        self:RefreshMainWindow()
    end)
    toolbar:AddChild(scanBtn)
    
    -- Sort button
    local sortBtn = AceGUI:Create("Button")
    sortBtn:SetText(L["BTN_SORT"])
    sortBtn:SetWidth(100)
    sortBtn:SetCallback("OnClick", function()
        self:SortWarbandBank()
    end)
    toolbar:AddChild(sortBtn)
    
    -- Deposit button
    local depositBtn = AceGUI:Create("Button")
    depositBtn:SetText(L["BTN_DEPOSIT"])
    depositBtn:SetWidth(120)
    depositBtn:SetCallback("OnClick", function()
        self:ShowDepositQueueUI()
    end)
    toolbar:AddChild(depositBtn)
    
    -- Settings button
    local settingsBtn = AceGUI:Create("Button")
    settingsBtn:SetText(L["BTN_SETTINGS"])
    settingsBtn:SetWidth(100)
    settingsBtn:SetCallback("OnClick", function()
        self:OpenOptions()
    end)
    toolbar:AddChild(settingsBtn)
    
    -- Tab container
    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    tabGroup:SetLayout("Fill")
    
    -- Build tab list - Main categories
    local tabs = {
        { value = "warband", text = L["TAB_WARBAND_BANK"] },
        { value = "personal", text = L["TAB_PERSONAL_BANK"] },
        { value = "stats", text = L["STATS_HEADER"] },
    }
    
    tabGroup:SetTabs(tabs)
    tabGroup:SetCallback("OnGroupSelected", function(widget, event, group)
        self:SelectTab(widget, group)
    end)
    frame:AddChild(tabGroup)
    frame.tabGroup = tabGroup
    
    -- Select default tab (will be overridden by bank type detection)
    tabGroup:SelectTab("warband")
    
    return frame
end

--[[
    Handle tab selection
    @param container AceGUI.TabGroup The tab container
    @param group string The selected tab value
]]
function WarbandNexus:SelectTab(container, group)
    container:ReleaseChildren()
    
    -- Store current tab for reference
    if mainFrame then
        mainFrame.currentTabGroup = group
    end
    
    if group == "stats" then
        self:DrawStatsTab(container)
    elseif group == "warband" then
        self:DrawWarbandBankTab(container)
    elseif group == "personal" then
        self:DrawPersonalBankTab(container)
    end
end

--[[
    Draw the Warband Bank tab with sub-tabs for each bank tab
    @param container AceGUI container
]]
function WarbandNexus:DrawWarbandBankTab(container)
    -- Create sub-tab group for Warband tabs
    local subTabGroup = AceGUI:Create("TabGroup")
    subTabGroup:SetFullWidth(true)
    subTabGroup:SetFullHeight(true)
    subTabGroup:SetLayout("Fill")
    
    -- Build sub-tab list
    local subTabs = {
        { value = "all", text = L["CATEGORY_ALL"] },
    }
    for i = 1, ns.WARBAND_TAB_COUNT do
        if not self.db.profile.ignoredTabs[i] then
            table.insert(subTabs, { value = "tab" .. i, text = L["TAB_" .. i] })
        end
    end
    
    subTabGroup:SetTabs(subTabs)
    subTabGroup:SetCallback("OnGroupSelected", function(widget, event, group)
        self:SelectWarbandSubTab(widget, group)
    end)
    container:AddChild(subTabGroup)
    
    -- Select first sub-tab
    subTabGroup:SelectTab("all")
end

--[[
    Handle Warband sub-tab selection
    @param container AceGUI.TabGroup The sub-tab container
    @param group string The selected sub-tab value
]]
function WarbandNexus:SelectWarbandSubTab(container, group)
    container:ReleaseChildren()
    
    local tabFilter = nil
    if group ~= "all" then
        tabFilter = tonumber(string.match(group, "tab(%d+)"))
    end
    
    self:DrawWarbandItemsTab(container, tabFilter)
end

--[[
    Draw Warband items tab content
    @param container AceGUI container
    @param tabFilter number|nil Tab number to filter by (nil = all)
]]
function WarbandNexus:DrawWarbandItemsTab(container, tabFilter)
    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("Flow")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)
    
    -- Store reference for filtering
    if mainFrame then
        mainFrame.scrollFrame = scrollFrame
        mainFrame.currentWarbandTab = tabFilter
    end
    
    -- Get items from cache
    local cache = self.db.global.warbandCache or {}
    local itemCount = 0
    
    for tabIndex, tabData in pairs(cache) do
        -- Filter by tab if specified
        if not tabFilter or tabFilter == tabIndex then
            for slotID, itemData in pairs(tabData) do
                itemCount = itemCount + 1
                
                -- Create item row
                local itemGroup = AceGUI:Create("SimpleGroup")
                itemGroup:SetFullWidth(true)
                itemGroup:SetHeight(30)
                itemGroup:SetLayout("Flow")
                scrollFrame:AddChild(itemGroup)
                
                -- Item icon (using label for now)
                local iconLabel = AceGUI:Create("Label")
                iconLabel:SetWidth(24)
                if itemData.iconFileID then
                    iconLabel:SetText("|T" .. itemData.iconFileID .. ":24:24|t")
                else
                    iconLabel:SetText("|TInterface\\Icons\\INV_Misc_QuestionMark:24:24|t")
                end
                itemGroup:AddChild(iconLabel)
                
                -- Item link/name
                local itemLabel = AceGUI:Create("InteractiveLabel")
                itemLabel:SetWidth(300)
                itemLabel:SetText(itemData.itemLink or ("Item #" .. itemData.itemID))
                
                -- Color by quality
                if itemData.quality and QUALITY_COLORS[itemData.quality] then
                    local color = QUALITY_COLORS[itemData.quality]
                    itemLabel:SetColor(color.r, color.g, color.b)
                end
                
                -- Tooltip on hover
                itemLabel:SetCallback("OnEnter", function(widget)
                    if itemData.itemLink then
                        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(itemData.itemLink)
                        GameTooltip:Show()
                    end
                end)
                itemLabel:SetCallback("OnLeave", function()
                    GameTooltip:Hide()
                end)
                itemGroup:AddChild(itemLabel)
                
                -- Stack count
                local countLabel = AceGUI:Create("Label")
                countLabel:SetWidth(60)
                countLabel:SetText("x" .. (itemData.stackCount or 1))
                itemGroup:AddChild(countLabel)
                
                -- Location
                local locLabel = AceGUI:Create("Label")
                locLabel:SetWidth(120)
                locLabel:SetText(L["TAB_" .. tabIndex] .. ", " .. L["TOOLTIP_SLOT"] .. " " .. slotID)
                locLabel:SetColor(0.7, 0.7, 0.7)
                itemGroup:AddChild(locLabel)
            end
        end
    end
    
    -- Show empty message if no items
    if itemCount == 0 then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetFullWidth(true)
        emptyLabel:SetText("\n\n" .. L["WARBAND_BANK_EMPTY"] .. "\n\n" .. L["WARBAND_BANK_SCAN_HINT"])
        emptyLabel:SetColor(0.7, 0.7, 0.7)
        scrollFrame:AddChild(emptyLabel)
    end
end

--[[
    Draw the Personal Bank tab
    @param container AceGUI container
]]
function WarbandNexus:DrawPersonalBankTab(container)
    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("Flow")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)
    
    -- Store reference
    if mainFrame then
        mainFrame.personalScrollFrame = scrollFrame
    end
    
    -- Get items from personal bank cache
    local cache = self.db.char.personalBankCache or {}
    local itemCount = 0
    
    for bagID, bagData in pairs(cache) do
        for slotID, itemData in pairs(bagData) do
            itemCount = itemCount + 1
            
            -- Create item row
            local itemGroup = AceGUI:Create("SimpleGroup")
            itemGroup:SetFullWidth(true)
            itemGroup:SetHeight(30)
            itemGroup:SetLayout("Flow")
            scrollFrame:AddChild(itemGroup)
            
            -- Item icon
            local iconLabel = AceGUI:Create("Label")
            iconLabel:SetWidth(24)
            if itemData.iconFileID then
                iconLabel:SetText("|T" .. itemData.iconFileID .. ":24:24|t")
            else
                iconLabel:SetText("|TInterface\\Icons\\INV_Misc_QuestionMark:24:24|t")
            end
            itemGroup:AddChild(iconLabel)
            
            -- Item link/name
            local itemLabel = AceGUI:Create("InteractiveLabel")
            itemLabel:SetWidth(300)
            itemLabel:SetText(itemData.itemLink or ("Item #" .. itemData.itemID))
            
            -- Color by quality
            if itemData.quality and QUALITY_COLORS[itemData.quality] then
                local color = QUALITY_COLORS[itemData.quality]
                itemLabel:SetColor(color.r, color.g, color.b)
            end
            
            -- Tooltip on hover
            itemLabel:SetCallback("OnEnter", function(widget)
                if itemData.itemLink then
                    GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(itemData.itemLink)
                    GameTooltip:Show()
                end
            end)
            itemLabel:SetCallback("OnLeave", function()
                GameTooltip:Hide()
            end)
            itemGroup:AddChild(itemLabel)
            
            -- Stack count
            local countLabel = AceGUI:Create("Label")
            countLabel:SetWidth(60)
            countLabel:SetText("x" .. (itemData.stackCount or 1))
            itemGroup:AddChild(countLabel)
            
            -- Location
            local locLabel = AceGUI:Create("Label")
            locLabel:SetWidth(120)
            local bagName = self:GetBagName(bagID)
            locLabel:SetText(bagName .. ", " .. L["TOOLTIP_SLOT"] .. " " .. slotID)
            locLabel:SetColor(0.7, 0.7, 0.7)
            itemGroup:AddChild(locLabel)
        end
    end
    
    -- Show empty message if no items
    if itemCount == 0 then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetFullWidth(true)
        emptyLabel:SetText("\n\n" .. L["PERSONAL_BANK_EMPTY"] .. "\n\n" .. L["PERSONAL_BANK_SCAN_HINT"])
        emptyLabel:SetColor(0.7, 0.7, 0.7)
        scrollFrame:AddChild(emptyLabel)
    end
end

--[[
    Get display name for a bag ID
    @param bagID number The bag ID
    @return string The display name
]]
function WarbandNexus:GetBagName(bagID)
    if bagID == Enum.BagIndex.Bank then
        return L["BAG_BANK_MAIN"]
    elseif bagID >= Enum.BagIndex.BankBag_1 and bagID <= Enum.BagIndex.BankBag_7 then
        local bagNum = bagID - Enum.BagIndex.BankBag_1 + 1
        return string.format(L["BAG_BANK_SLOT"], bagNum)
    elseif bagID == Enum.BagIndex.Reagentbank then
        return L["BAG_REAGENT_BANK"]
    end
    return "Bag " .. bagID
end

--[[
    Draw the statistics tab
    @param container AceGUI container
]]
function WarbandNexus:DrawStatsTab(container)
    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("List")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)
    
    local stats = self:GetBankStatistics()
    
    -- Header
    local header = AceGUI:Create("Heading")
    header:SetFullWidth(true)
    header:SetText(L["STATS_HEADER"])
    scrollFrame:AddChild(header)
    
    -- Statistics display
    local function AddStat(label, value)
        local statGroup = AceGUI:Create("SimpleGroup")
        statGroup:SetFullWidth(true)
        statGroup:SetLayout("Flow")
        scrollFrame:AddChild(statGroup)
        
        local labelWidget = AceGUI:Create("Label")
        labelWidget:SetWidth(200)
        labelWidget:SetText(label .. ":")
        labelWidget:SetColor(0.8, 0.8, 0.8)
        statGroup:AddChild(labelWidget)
        
        local valueWidget = AceGUI:Create("Label")
        valueWidget:SetWidth(200)
        valueWidget:SetText(tostring(value))
        valueWidget:SetColor(1, 1, 1)
        statGroup:AddChild(valueWidget)
    end
    
    AddStat(L["STATS_TOTAL_SLOTS"], stats.totalSlots)
    AddStat(L["STATS_USED_SLOTS"], stats.usedSlots)
    AddStat(L["STATS_FREE_SLOTS"], stats.freeSlots)
    AddStat(L["STATS_TOTAL_ITEMS"], stats.totalItems)
    AddStat(L["STATS_TOTAL_VALUE"], GetCoinTextureString(stats.totalValue))
    
    -- Last scan time
    if stats.lastScanTime > 0 then
        local lastScan = date("%Y-%m-%d %H:%M:%S", stats.lastScanTime)
        AddStat("Last Scan", lastScan)
    end
    
    -- Quality breakdown
    local qualityHeader = AceGUI:Create("Heading")
    qualityHeader:SetFullWidth(true)
    qualityHeader:SetText("Items by Quality")
    scrollFrame:AddChild(qualityHeader)
    
    local qualityNames = {
        [0] = L["QUALITY_POOR"],
        [1] = L["QUALITY_COMMON"],
        [2] = L["QUALITY_UNCOMMON"],
        [3] = L["QUALITY_RARE"],
        [4] = L["QUALITY_EPIC"],
        [5] = L["QUALITY_LEGENDARY"],
        [6] = L["QUALITY_ARTIFACT"],
        [7] = L["QUALITY_HEIRLOOM"],
    }
    
    for quality = 0, 7 do
        local count = stats.itemsByQuality[quality] or 0
        if count > 0 then
            local color = QUALITY_COLORS[quality]
            local qualityGroup = AceGUI:Create("SimpleGroup")
            qualityGroup:SetFullWidth(true)
            qualityGroup:SetLayout("Flow")
            scrollFrame:AddChild(qualityGroup)
            
            local nameLabel = AceGUI:Create("Label")
            nameLabel:SetWidth(200)
            nameLabel:SetText(qualityNames[quality] or ("Quality " .. quality))
            nameLabel:SetColor(color.r, color.g, color.b)
            qualityGroup:AddChild(nameLabel)
            
            local countLabel = AceGUI:Create("Label")
            countLabel:SetWidth(100)
            countLabel:SetText(tostring(count))
            qualityGroup:AddChild(countLabel)
        end
    end
    
    -- Warband bank money
    local moneyHeader = AceGUI:Create("Heading")
    moneyHeader:SetFullWidth(true)
    moneyHeader:SetText("Warband Bank Gold")
    scrollFrame:AddChild(moneyHeader)
    
    local warbandMoney = self:GetWarbandBankMoney()
    AddStat("Warband Bank", GetCoinTextureString(warbandMoney))
    AddStat("Character Gold", GetCoinTextureString(GetMoney()))
    AddStat("Depositable", GetCoinTextureString(self:GetDepositableGold()))
    
    -- Deposit gold button
    local depositGoldBtn = AceGUI:Create("Button")
    depositGoldBtn:SetText(L["BTN_DEPOSIT_GOLD"])
    depositGoldBtn:SetWidth(150)
    depositGoldBtn:SetCallback("OnClick", function()
        self:DepositGold()
    end)
    scrollFrame:AddChild(depositGoldBtn)
end

--[[
    Filter items in main window
    @param searchText string The search text
]]
function WarbandNexus:FilterMainWindowItems(searchText)
    if not mainFrame or not mainFrame.tabGroup then
        return
    end
    
    -- For now, just refresh and let SearchCachedItems handle filtering
    -- A more efficient implementation would filter the displayed widgets
    self:Debug("Filtering by: " .. tostring(searchText))
    
    -- Refresh current tab
    local currentGroup = mainFrame.currentTabGroup or "warband"
    mainFrame.tabGroup:SelectTab(currentGroup)
end

--[[
    Refresh the main window content
    Note: This only refreshes the current tab's content, does NOT change tabs
]]
function WarbandNexus:RefreshMainWindow()
    if not mainFrame or not mainFrame.tabGroup then
        self:Debug("RefreshMainWindow: mainFrame or tabGroup not ready")
        return
    end
    
    -- Only refresh if we have a current tab set
    local currentGroup = mainFrame.currentTabGroup
    if not currentGroup then
        self:Debug("RefreshMainWindow: no currentTabGroup set, skipping")
        return
    end
    
    self:Debug(string.format("RefreshMainWindow: refreshing tab %s", currentGroup))
    
    -- Re-select current tab to refresh its content
    mainFrame.tabGroup:SelectTab(currentGroup)
end

--[[
    Select a specific tab in the main window
    @param tabName string The tab name to select ("warband", "personal", "stats")
]]
function WarbandNexus:SelectMainWindowTab(tabName)
    if not mainFrame then
        self:ShowMainWindow()
    end
    
    if mainFrame and mainFrame.tabGroup then
        mainFrame.tabGroup:SelectTab(tabName)
    end
end

--[[
    Show main window and select appropriate tab based on bank type
    Called when bank is opened - shows Items tab (warband or personal)
    @param bankType string|nil "warband", "personal", or nil for default
]]
function WarbandNexus:ShowMainWindowWithTab(bankType)
    self:Debug(string.format("ShowMainWindowWithTab (bank open): bankType=%s", tostring(bankType)))
    
    -- Create frame if it doesn't exist
    if not mainFrame then
        mainFrame = self:CreateMainWindow()
    end
    
    -- Bank open always shows the appropriate items tab
    local targetTab = bankType or "warband"
    mainFrame.currentTabGroup = targetTab
    
    self:Debug(string.format("ShowMainWindowWithTab: selecting Items tab: %s", targetTab))
    
    -- Select the bank items tab
    if mainFrame.tabGroup then
        mainFrame.tabGroup:SelectTab(targetTab)
    end
    
    mainFrame:Show()
end

--[[
    Refresh UI elements (called on profile change, scan complete, etc.)
    Note: Does NOT change the current tab, only refreshes content
]]
function WarbandNexus:RefreshUI()
    self:Debug("RefreshUI called")
    
    if mainFrame and mainFrame:IsShown() then
        -- Only refresh if there's a tab already set
        if mainFrame.currentTabGroup then
            self:Debug(string.format("RefreshUI: refreshing current tab %s", mainFrame.currentTabGroup))
            self:RefreshMainWindow()
        end
    end
    
    if depositQueueFrame and depositQueueFrame:IsShown() then
        self:RefreshDepositQueueUI()
    end
end

--[[
    Show deposit queue UI
]]
function WarbandNexus:ShowDepositQueueUI()
    if not depositQueueFrame then
        depositQueueFrame = self:CreateDepositQueueWindow()
    end
    
    self:RefreshDepositQueueUI()
    depositQueueFrame:Show()
end

--[[
    Create deposit queue window
    @return AceGUI.Frame
]]
function WarbandNexus:CreateDepositQueueWindow()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle(L["BTN_DEPOSIT"])
    frame:SetLayout("Flow")
    frame:SetWidth(400)
    frame:SetHeight(350)
    
    frame:SetCallback("OnClose", function(widget)
        widget:Hide()
    end)
    
    -- Toolbar
    local toolbar = AceGUI:Create("SimpleGroup")
    toolbar:SetFullWidth(true)
    toolbar:SetLayout("Flow")
    frame:AddChild(toolbar)
    
    -- Clear queue button
    local clearBtn = AceGUI:Create("Button")
    clearBtn:SetText(L["BTN_CLEAR_QUEUE"])
    clearBtn:SetWidth(120)
    clearBtn:SetCallback("OnClick", function()
        self:ClearDepositQueue()
        self:RefreshDepositQueueUI()
    end)
    toolbar:AddChild(clearBtn)
    
    -- Deposit gold button
    local depositGoldBtn = AceGUI:Create("Button")
    depositGoldBtn:SetText(L["BTN_DEPOSIT_GOLD"])
    depositGoldBtn:SetWidth(120)
    depositGoldBtn:SetCallback("OnClick", function()
        self:DepositGold()
    end)
    toolbar:AddChild(depositGoldBtn)
    
    -- Queue list
    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("List")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    frame:AddChild(scrollFrame)
    frame.scrollFrame = scrollFrame
    
    return frame
end

--[[
    Refresh deposit queue UI
]]
function WarbandNexus:RefreshDepositQueueUI()
    if not depositQueueFrame or not depositQueueFrame.scrollFrame then
        return
    end
    
    local scrollFrame = depositQueueFrame.scrollFrame
    scrollFrame:ReleaseChildren()
    
    local queue = self.db.char.depositQueue
    
    if not queue or #queue == 0 then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetFullWidth(true)
        emptyLabel:SetText("\n" .. L["DEPOSIT_QUEUE_EMPTY"])
        emptyLabel:SetColor(0.7, 0.7, 0.7)
        scrollFrame:AddChild(emptyLabel)
        return
    end
    
    for i, item in ipairs(queue) do
        local itemGroup = AceGUI:Create("SimpleGroup")
        itemGroup:SetFullWidth(true)
        itemGroup:SetLayout("Flow")
        scrollFrame:AddChild(itemGroup)
        
        -- Item info
        local itemLabel = AceGUI:Create("InteractiveLabel")
        itemLabel:SetWidth(250)
        itemLabel:SetText(item.itemLink or ("Item #" .. item.itemID))
        
        if item.quality and QUALITY_COLORS[item.quality] then
            local color = QUALITY_COLORS[item.quality]
            itemLabel:SetColor(color.r, color.g, color.b)
        end
        
        itemLabel:SetCallback("OnEnter", function(widget)
            if item.itemLink then
                GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(item.itemLink)
                GameTooltip:Show()
            end
        end)
        itemLabel:SetCallback("OnLeave", function()
            GameTooltip:Hide()
        end)
        itemGroup:AddChild(itemLabel)
        
        -- Count
        local countLabel = AceGUI:Create("Label")
        countLabel:SetWidth(50)
        countLabel:SetText("x" .. (item.count or 1))
        itemGroup:AddChild(countLabel)
        
        -- Remove button
        local removeBtn = AceGUI:Create("Button")
        removeBtn:SetText("X")
        removeBtn:SetWidth(30)
        removeBtn:SetCallback("OnClick", function()
            self:RemoveFromDepositQueue(i)
            self:RefreshDepositQueueUI()
        end)
        itemGroup:AddChild(removeBtn)
    end
end


