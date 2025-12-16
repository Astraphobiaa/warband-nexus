local WarbandNexus = LibStub("AceAddon-3.0"):GetAddon("WarbandNexus")
local UI = WarbandNexus:NewModule("UI", "AceEvent-3.0", "AceTimer-3.0")
local AceGUI = LibStub("AceGUI-3.0")

-- State variables
local frame = nil
local currentTab = "chars" -- chars, items, pve, stats
local currentItemsSubTab = "warband" -- warband, personal
local searchQuery = ""
local activeContainer = nil -- References the active AceGUI container for content

function UI:OnEnable()
    -- Pre-load standard font strings or textures if needed
end

-- Setter for Items SubTab
function UI:SetItemsSubTab(tabName)
    if tabName == "warband" or tabName == "personal" then
        currentItemsSubTab = tabName
    end
end

-- Create the main window frame
function UI:CreateFrame()
    if frame then return frame end

    frame = AceGUI:Create("Frame")
    frame:SetTitle("Warband Nexus")
    frame:SetStatusText("Ready")
    frame:SetLayout("Fill")
    frame:SetWidth(800)
    frame:SetHeight(600)
    frame:SetCallback("OnClose", function(widget) 
        widget:Hide() 
    end)

    -- Main Tab Group
    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("Flow")
    tabGroup:SetTabs({
        {text = "Characters", value = "chars"},
        {text = "Items", value = "items"},
        {text = "PvE Progress", value = "pve"},
        {text = "Statistics", value = "stats"}
    })
    
    tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        currentTab = group
        activeContainer = container
        container:ReleaseChildren()
        
        if group == "chars" then
            self:DrawCharacterList(container)
        elseif group == "items" then
            self:DrawItemList(container)
        elseif group == "pve" then
            self:DrawPvEProgress(container)
        elseif group == "stats" then
            self:DrawStatistics(container)
        end
    end)
    
    frame:AddChild(tabGroup)
    self.tabGroup = tabGroup
    
    return frame
end

-- Show the window (Default: Characters tab) - Used for /wn show or minimap
function UI:ShowMainWindow()
    local f = self:CreateFrame()
    f:Show()
    -- Default to Characters tab for manual open
    self.tabGroup:SelectTab("chars")
end

-- Show the window with Items tab active - Used for Bank NPC interaction
function UI:ShowMainWindowWithItems(bankType)
    local f = self:CreateFrame()
    f:Show()
    
    -- Set the sub-tab state BEFORE drawing
    if bankType then
        self:SetItemsSubTab(bankType)
    end
    
    -- Select the Items tab
    self.tabGroup:SelectTab("items")
end

function UI:HideMainWindow()
    if frame then
        frame:Hide()
    end
end

function UI:IsFrameShown()
    return frame and frame:IsShown()
end

function UI:RefreshItemList()
    if frame and frame:IsShown() and currentTab == "items" and activeContainer then
        activeContainer:ReleaseChildren()
        self:DrawItemList(activeContainer)
    end
end

function UI:RefreshMoneyDisplay()
    -- Logic to update money text only without redrawing everything could go here
    -- For now, full refresh is safer
    self:RefreshItemList()
end

-- --- CHARACTERS TAB ---
function UI:DrawCharacterList(container)
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)
    
    local chars = WarbandNexus.db.global.characters or {}
    
    for charKey, charData in pairs(chars) do
        local group = AceGUI:Create("InlineGroup")
        group:SetTitle(charKey)
        group:SetFullWidth(true)
        group:SetLayout("Flow")
        
        local info = AceGUI:Create("Label")
        info:SetText(string.format("Gold: %s", GetCoinTextureString(charData.money or 0)))
        info:SetFullWidth(true)
        group:AddChild(info)
        
        scroll:AddChild(group)
    end
end

-- --- ITEMS TAB ---
function UI:DrawItemList(container)
    -- Top Bar: Search and Filters
    local topGroup = AceGUI:Create("SimpleGroup")
    topGroup:SetLayout("Flow")
    topGroup:SetFullWidth(true)
    container:AddChild(topGroup)
    
    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("Search Items")
    searchBox:SetText(searchQuery)
    searchBox:SetWidth(200)
    searchBox:SetCallback("OnEnterPressed", function(widget, event, text)
        searchQuery = text
        self:RefreshItemList()
    end)
    topGroup:AddChild(searchBox)
    
    -- Bank Selection Buttons (Personal vs Warband)
    local btnPersonal = AceGUI:Create("Button")
    btnPersonal:SetText("Personal Bank")
    btnPersonal:SetWidth(120)
    btnPersonal:SetCallback("OnClick", function() 
        currentItemsSubTab = "personal"
        self:SyncBankTab()
        self:RefreshItemList()
    end)
    topGroup:AddChild(btnPersonal)
    
    local btnWarband = AceGUI:Create("Button")
    btnWarband:SetText("Warband Bank")
    btnWarband:SetWidth(120)
    btnWarband:SetCallback("OnClick", function() 
        currentItemsSubTab = "warband"
        self:SyncBankTab()
        self:RefreshItemList()
    end)
    topGroup:AddChild(btnWarband)

    -- Highlight active tab button
    if currentItemsSubTab == "personal" then
        btnPersonal:SetDisabled(true)
    else
        btnWarband:SetDisabled(true)
    end
    
    -- Money Display and Transfer Buttons
    local moneyGroup = AceGUI:Create("SimpleGroup")
    moneyGroup:SetLayout("Flow")
    moneyGroup:SetFullWidth(true)
    container:AddChild(moneyGroup)

    local moneyLabel = AceGUI:Create("Label")
    moneyLabel:SetWidth(200)
    
    -- Determine which money to show
    if currentItemsSubTab == "warband" then
        local warbandMoney = C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
        moneyLabel:SetText("Warband: " .. GetCoinTextureString(warbandMoney))
    else
        moneyLabel:SetText("Character: " .. GetCoinTextureString(GetMoney()))
    end
    moneyGroup:AddChild(moneyLabel)

    -- Gold Transfer Buttons (Only for Warband Bank)
    if currentItemsSubTab == "warband" then
        local btnDeposit = AceGUI:Create("Button")
        btnDeposit:SetText("Deposit Gold")
        btnDeposit:SetWidth(110)
        btnDeposit:SetCallback("OnClick", function()
            self:ShowGoldTransferPopup("warband", "deposit")
        end)
        moneyGroup:AddChild(btnDeposit)

        local btnWithdraw = AceGUI:Create("Button")
        btnWithdraw:SetText("Withdraw Gold")
        btnWithdraw:SetWidth(110)
        btnWithdraw:SetCallback("OnClick", function()
            self:ShowGoldTransferPopup("warband", "withdraw")
        end)
        moneyGroup:AddChild(btnWithdraw)
    else
        -- Spacer or disabled buttons for personal bank if desired
        -- Personal bank doesn't store gold in the same way (it's on the character)
        local infoLabel = AceGUI:Create("Label")
        infoLabel:SetText("(Personal Bank stores items only)")
        infoLabel:SetColor(0.5, 0.5, 0.5)
        moneyGroup:AddChild(infoLabel)
    end
    
    -- Item List Scroll Frame
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)
    
    -- Get items based on subtab
    local items = {}
    if currentItemsSubTab == "warband" then
        items = WarbandNexus.db.global.warbandCache or {}
    else
        items = WarbandNexus.db.global.characters[UnitName("player")] and WarbandNexus.db.global.characters[UnitName("player")].bank or {}
    end
    
    -- Render Items
    for _, item in pairs(items) do
        if not searchQuery or searchQuery == "" or (item.link and string.find(string.lower(item.link), string.lower(searchQuery))) then
            self:CreateItemWidget(scroll, item)
        end
    end
end

-- Synchronize the actual WoW Bank Frame with our UI
function UI:SyncBankTab()
    if not C_Bank.IsOpen() then return end
    
    -- Modern API approach for TWW
    -- 1 = Character Bank, 2 = Warband Bank, 3 = Reagent Bank
    local targetTabID = 1
    if currentItemsSubTab == "warband" then
        targetTabID = 2
    end
    
    -- Check if we are already on the correct tab to avoid redundant calls
    local currentBankTab = C_Bank.GetActiveBankTab()
    
    if currentBankTab ~= targetTabID then
        -- Use BankFrame:SetTab to switch tabs securely
        if BankFrame and BankFrame.SetTab then
             BankFrame:SetTab(targetTabID)
        end
    end
end

function UI:CreateItemWidget(container, item)
    local itemGroup = AceGUI:Create("SimpleGroup")
    itemGroup:SetLayout("Flow")
    itemGroup:SetWidth(300) 
    
    local icon = AceGUI:Create("Icon")
    icon:SetImage(item.icon or "Interface\\Icons\\Inv_misc_questionmark")
    icon:SetImageSize(32, 32)
    icon:SetWidth(40)
    icon:SetCallback("OnClick", function(widget, button)
        if button == "LeftButton" then
             if IsShiftKeyDown() then
                 ChatEdit_InsertLink(item.link)
             else
                 -- Logic to move item
                 self:MoveItem(item)
             end
        end
    end)
    itemGroup:AddChild(icon)
    
    local label = AceGUI:Create("InteractiveLabel")
    label:SetText((item.link or "Unknown") .. " x" .. (item.count or 1))
    label:SetWidth(240)
    itemGroup:AddChild(label)
    
    container:AddChild(itemGroup)
end

function UI:MoveItem(item)
    -- Simple logic: If in bag, deposit to bank. If in bank, withdraw to bag.
    -- Requires secure environment or careful API usage.
    -- For now, we will just print/debug as auto-move requires protected calls or hardware event wrapper.
    if not C_Bank.IsOpen() then 
        WarbandNexus:Print("Bank must be open to move items.")
        return 
    end
    
    -- Note: Actual movement logic (PickupContainerItem) requires hardware event if not automated.
    -- We can only facilitate "Click to move" if the widget is a SecureActionButton.
    -- Since AceGUI icons are not secure, we can only support this if we rewrite using SecureTemplates.
    -- For this version, we'll implement a safe fallback or skip.
    
    WarbandNexus:Print("Right-click items in your bag/bank to move them quickly while this window is open.")
end

-- --- GOLD TRANSFER POPUP ---
local goldPopup = nil
local goldInput = nil
local silverInput = nil
local copperInput = nil
local activeTransactionMode = nil -- "deposit" or "withdraw"

function UI:CreateGoldTransferPopup()
    if goldPopup then return goldPopup end
    
    local f = AceGUI:Create("Window")
    f:SetTitle("Gold Transfer")
    f:SetLayout("Flow")
    f:SetWidth(300)
    f:SetHeight(250)
    f:EnableResize(false)
    f:Hide()
    
    -- Amount Inputs
    local grp = AceGUI:Create("SimpleGroup")
    grp:SetLayout("Flow")
    grp:SetFullWidth(true)
    f:AddChild(grp)
    
    goldInput = AceGUI:Create("EditBox")
    goldInput:SetLabel("Gold")
    goldInput:SetWidth(80)
    grp:AddChild(goldInput)
    
    silverInput = AceGUI:Create("EditBox")
    silverInput:SetLabel("Silver")
    silverInput:SetWidth(80)
    grp:AddChild(silverInput)
    
    copperInput = AceGUI:Create("EditBox")
    copperInput:SetLabel("Copper")
    copperInput:SetWidth(80)
    grp:AddChild(copperInput)
    
    -- Quick Buttons
    local function AddQuickBtn(text, amount)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        btn:SetWidth(60)
        btn:SetUserData("amount", amount)
        btn:SetCallback("OnClick", function()
             self:FillMoneyInput(amount)
        end)
        f:AddChild(btn)
        return btn
    end
    
    self.quickBtns = {}
    table.insert(self.quickBtns, AddQuickBtn("10k", 10000 * 10000))
    table.insert(self.quickBtns, AddQuickBtn("100k", 100000 * 10000))
    table.insert(self.quickBtns, AddQuickBtn("500k", 500000 * 10000))
    table.insert(self.quickBtns, AddQuickBtn("1m", 1000000 * 10000))
    table.insert(self.quickBtns, AddQuickBtn("All", -1)) -- Special value
    
    -- Action Button
    local actionBtn = AceGUI:Create("Button")
    actionBtn:SetText("Confirm")
    actionBtn:SetFullWidth(true)
    actionBtn:SetCallback("OnClick", function()
        self:ExecuteGoldTransaction()
    end)
    f:AddChild(actionBtn)
    self.goldActionBtn = actionBtn
    
    goldPopup = f
    return goldPopup
end

function UI:ShowGoldTransferPopup(bankType, mode)
    if bankType ~= "warband" then return end -- Only warband supports gold deposit/withdraw via this UI
    
    local popup = self:CreateGoldTransferPopup()
    popup:Show()
    popup:SetTitle(mode == "deposit" and "Deposit to Warband" or "Withdraw from Warband")
    self.goldActionBtn:SetText(mode == "deposit" and "Deposit" or "Withdraw")
    
    activeTransactionMode = mode
    
    -- Reset inputs
    goldInput:SetText("")
    silverInput:SetText("")
    copperInput:SetText("")
    
    self:UpdateGoldTransferButtons()
end

function UI:RefreshGoldPopup()
    if goldPopup and goldPopup:IsShown() then
        self:UpdateGoldTransferButtons()
    end
end

function UI:UpdateGoldTransferButtons()
    -- Check available funds
    local available = 0
    if activeTransactionMode == "deposit" then
        available = GetMoney()
    else
        available = C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
    end
    
    for _, btn in ipairs(self.quickBtns) do
        local amt = btn:GetUserData("amount")
        if amt == -1 then
             -- "All" button always enabled if > 0
             btn:SetDisabled(available <= 0)
        else
             btn:SetDisabled(available < amt)
        end
    end
end

function UI:FillMoneyInput(copperAmount)
    local available = 0
    if activeTransactionMode == "deposit" then
        available = GetMoney()
    else
        available = C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
    end

    if copperAmount == -1 then
        copperAmount = available
    end
    
    local gold = math.floor(copperAmount / 10000)
    local silver = math.floor((copperAmount % 10000) / 100)
    local copper = copperAmount % 100
    
    goldInput:SetText(tostring(gold))
    silverInput:SetText(tostring(silver))
    copperInput:SetText(tostring(copper))
end

function UI:ExecuteGoldTransaction()
    local g = tonumber(goldInput:GetText()) or 0
    local s = tonumber(silverInput:GetText()) or 0
    local c = tonumber(copperInput:GetText()) or 0
    
    local totalCopper = (g * 10000) + (s * 100) + c
    
    if totalCopper <= 0 then return end
    
    if activeTransactionMode == "deposit" then
        C_Bank.DepositMoney(Enum.BankType.Account, totalCopper)
    elseif activeTransactionMode == "withdraw" then
        C_Bank.WithdrawMoney(Enum.BankType.Account, totalCopper)
    end
    
    -- Close popup on success
    goldPopup:Hide()
    
    -- Refresh UI will happen via events PLAYER_MONEY / ACCOUNT_MONEY
end

-- --- PVE & STATS TABS (Placeholders) ---
function UI:DrawPvEProgress(container)
    local label = AceGUI:Create("Label")
    label:SetText("PvE Progress functionality coming soon.")
    container:AddChild(label)
end

function UI:DrawStatistics(container)
    local label = AceGUI:Create("Label")
    label:SetText("Statistics functionality coming soon.")
    container:AddChild(label)
end
