--[[
    Warband Nexus - Banker Module
    Handles gold and item deposit operations
    Implements offline caching for Warband Bank access
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- Local references for performance
local wipe = wipe
local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert
local tremove = table.remove

-- Warband Bank snapshot cache
local warbandBankSnapshot = nil
local snapshotTimestamp = 0

--[[
    Create a snapshot of the Warband Bank
    Called when bank is opened to cache data for offline access
]]
function WarbandNexus:SnapshotWarbandBank()
    if not self.db or not self.db.global then
        return false
    end
    
    -- Initialize warband data structure
    if not self.db.global.warbandData then
        self.db.global.warbandData = {
            reputations = {},
            bank = {}
        }
    end
    
    -- Copy current Warband Bank data to snapshot
    if self.db.global.warbandBank then
        self.db.global.warbandData.bank = {
            items = self:DeepCopy(self.db.global.warbandBank.items or {}),
            gold = self.db.global.warbandBank.gold or 0,
            lastSnapshot = time(),
            totalSlots = self.db.global.warbandBank.totalSlots or 0,
            usedSlots = self.db.global.warbandBank.usedSlots or 0,
            tabs = self.db.global.warbandBank.tabs or {}
        }
        
        -- Update local cache
        warbandBankSnapshot = self.db.global.warbandData.bank
        snapshotTimestamp = time()
        
        self:Debug("Warband Bank snapshot created")
        return true
    end
    
    return false
end

--[[
    Get Warband Bank data (from snapshot if bank is closed)
    @return table - Bank data
]]
function WarbandNexus:GetWarbandBankData()
    -- If bank is open, use live data
    if self:IsWarbandBankOpen() and self.db.global.warbandBank then
        return self.db.global.warbandBank
    end
    
    -- Otherwise, use snapshot
    if not warbandBankSnapshot and self.db.global.warbandData and self.db.global.warbandData.bank then
        warbandBankSnapshot = self.db.global.warbandData.bank
        snapshotTimestamp = self.db.global.warbandData.bank.lastSnapshot or 0
    end
    
    return warbandBankSnapshot or {
        items = {},
        gold = 0,
        lastSnapshot = 0,
        totalSlots = 0,
        usedSlots = 0,
        tabs = {}
    }
end

--[[
    Get snapshot age in seconds
    @return number - Age in seconds, or -1 if no snapshot
]]
function WarbandNexus:GetSnapshotAge()
    local bankData = self:GetWarbandBankData()
    if not bankData or not bankData.lastSnapshot or bankData.lastSnapshot == 0 then
        return -1
    end
    
    return time() - bankData.lastSnapshot
end

--[[
    Get formatted snapshot age string
    @return string - Human-readable age
]]
function WarbandNexus:GetSnapshotAgeString()
    local age = self:GetSnapshotAge()
    
    if age < 0 then
        return "Never"
    elseif age < 60 then
        return string.format("%d seconds ago", age)
    elseif age < 3600 then
        return string.format("%d minutes ago", math.floor(age / 60))
    elseif age < 86400 then
        return string.format("%d hours ago", math.floor(age / 3600))
    else
        return string.format("%d days ago", math.floor(age / 86400))
    end
end

--[[
    Check if Warband Bank is open
    @return boolean
]]
function WarbandNexus:IsWarbandBankOpen()
    -- Check if bank frame is open and it's the account bank
    if not BankFrame or not BankFrame:IsShown() then
        return false
    end
    
    -- Check if we're viewing the account bank specifically
    if C_Bank and C_Bank.HasMaxExpansions then
        return C_Bank.HasMaxExpansions()
    end
    
    return false
end

--[[
    Open the deposit queue interface
    Shows items queued for deposit to Warband bank
]]
function WarbandNexus:OpenDepositQueue()
    if not self:IsWarbandBankOpen() then
        self:Print(L["BANK_NOT_OPEN"])
        return
    end
    
    -- Show deposit queue UI
    if self.ShowDepositQueueUI then
        self:ShowDepositQueueUI()
    else
        self:PrintDepositQueue()
    end
end

--[[
    Print deposit queue to chat (fallback when UI not available)
]]
function WarbandNexus:PrintDepositQueue()
    local queue = self.db.char.depositQueue
    
    if not queue or #queue == 0 then
        self:Print(L["DEPOSIT_QUEUE_EMPTY"])
        return
    end
    
    self:Print("Deposit Queue (" .. #queue .. " items):")
    for i, item in ipairs(queue) do
        self:Print(string.format("  %d. %s x%d", i, item.itemLink or ("Item #" .. item.itemID), item.count or 1))
    end
end

--[[
    Add an item to the deposit queue
    @param bagID number The source bag ID
    @param slotID number The source slot ID
    @return boolean Success
]]
function WarbandNexus:QueueItemForDeposit(bagID, slotID)
    local itemInfo = self:GetContainerItemInfo(bagID, slotID)
    
    if not itemInfo or not itemInfo.itemID then
        self:Print(L["ERROR_INVALID_ITEM"])
        return false
    end
    
    -- Check if item is already in queue
    for _, queuedItem in ipairs(self.db.char.depositQueue) do
        if queuedItem.bagID == bagID and queuedItem.slotID == slotID then
            return false
        end
    end
    
    -- Add to queue
    tinsert(self.db.char.depositQueue, {
        bagID = bagID,
        slotID = slotID,
        itemID = itemInfo.itemID,
        itemLink = itemInfo.hyperlink,
        count = itemInfo.stackCount or 1,
        quality = itemInfo.quality,
    })
    
    self:Print(string.format(L["ITEM_QUEUED"], itemInfo.hyperlink or ("Item #" .. itemInfo.itemID)))
    
    return true
end

--[[
    Remove an item from the deposit queue
    @param index number The queue index to remove
    @return boolean Success
]]
function WarbandNexus:RemoveFromDepositQueue(index)
    local queue = self.db.char.depositQueue
    
    if not queue or index < 1 or index > #queue then
        return false
    end
    
    local item = tremove(queue, index)
    
    if item then
        self:Print(string.format(L["ITEM_REMOVED"], item.itemLink or ("Item #" .. item.itemID)))
        return true
    end
    
    return false
end

--[[
    Clear the deposit queue
]]
function WarbandNexus:ClearDepositQueue()
    wipe(self.db.char.depositQueue)
    self:Print(L["DEPOSIT_QUEUE_CLEARED"])
end

--[[
    Process the deposit queue
    NOTE: This requires user interaction (clicking) per Blizzard ToS
    This function prepares items but does NOT automatically move them
    @return table Items ready for deposit with instructions
]]
function WarbandNexus:PrepareDeposit()
    if not self:IsWarbandBankOpen() then
        self:Print(L["BANK_NOT_OPEN"])
        return nil
    end
    
    local queue = self.db.char.depositQueue
    
    if not queue or #queue == 0 then
        self:Print(L["DEPOSIT_QUEUE_EMPTY"])
        return nil
    end
    
    -- Validate queue items still exist
    local validItems = {}
    
    for _, queuedItem in ipairs(queue) do
        local currentInfo = self:GetContainerItemInfo(queuedItem.bagID, queuedItem.slotID)
        
        if currentInfo and currentInfo.itemID == queuedItem.itemID then
            tinsert(validItems, {
                bagID = queuedItem.bagID,
                slotID = queuedItem.slotID,
                itemID = queuedItem.itemID,
                itemLink = queuedItem.itemLink,
                count = currentInfo.stackCount or 1,
            })
        else
        end
    end
    
    return validItems
end

--[[
    Get the amount of gold that can be deposited
    Respects the gold reserve setting
    @return number Amount in copper that can be deposited
]]
function WarbandNexus:GetDepositableGold()
    local currentGold = GetMoney()
    local reserveGold = self.db.profile.goldReserve * 10000 -- Convert gold to copper
    
    local depositable = currentGold - reserveGold
    
    return depositable > 0 and depositable or 0
end

--[[
    Deposit gold to Warband bank
    NOTE: This uses the protected C_Bank API which is ToS-compliant
    @param amount number|nil Amount in copper (nil = max depositable)
    @return boolean Success
]]
function WarbandNexus:DepositGold(amount)
    if not self:IsWarbandBankOpen() then
        self:Print(L["BANK_NOT_OPEN"])
        return false
    end
    
    -- Check if we're in combat (protected functions restricted)
    if InCombatLockdown() then
        self:Print(L["ERROR_PROTECTED_FUNCTION"])
        return false
    end
    
    local maxDepositable = self:GetDepositableGold()
    
    if maxDepositable <= 0 then
        self:Print(L["INSUFFICIENT_GOLD"])
        return false
    end
    
    -- Use specified amount or max
    local depositAmount = amount or maxDepositable
    depositAmount = math.min(depositAmount, maxDepositable)
    
    -- Use C_Bank API for Warband gold deposit
    if C_Bank and C_Bank.DepositMoney then
        C_Bank.DepositMoney(Enum.BankType.Account, depositAmount)
        
        -- Format gold display
        local goldText = GetCoinTextureString(depositAmount)
        self:Print(string.format(L["GOLD_DEPOSITED"], goldText))
        
        return true
    else
        self:Print(L["ERROR_API_UNAVAILABLE"])
        return false
    end
end

--[[
    Deposit specific gold amount (wrapper for UI)
    @param copper number Amount in copper
]]
function WarbandNexus:DepositGoldAmount(copper)
    if not copper or copper <= 0 then
        self:Print("|cffff6600Invalid amount.|r")
        return false
    end
    return self:DepositGold(copper)
end

--[[
    Withdraw gold from Warband bank
    @param copper number Amount in copper to withdraw
]]
function WarbandNexus:WithdrawGoldAmount(copper)
    if not self.bankIsOpen then
        self:Print("|cffff6600Bank must be open to withdraw!|r")
        return false
    end
    
    if InCombatLockdown() then
        self:Print("|cffff6600Cannot withdraw during combat.|r")
        return false
    end
    
    if not copper or copper <= 0 then
        self:Print("|cffff6600Invalid amount.|r")
        return false
    end
    
    local warbandGold = self:GetWarbandBankMoney()
    if copper > warbandGold then
        self:Print("|cffff6600Not enough gold in Warband bank.|r")
        return false
    end
    
    -- Use C_Bank API for withdrawal
    if C_Bank and C_Bank.WithdrawMoney then
        C_Bank.WithdrawMoney(Enum.BankType.Account, copper)
        local goldText = GetCoinTextureString(copper)
        self:Print("|cff00ff00Withdrawn:|r " .. goldText)
        return true
    else
        self:Print("|cffff6600Withdraw API not available.|r")
        return false
    end
end

--[[
    Get Warband bank gold balance
    @return number Amount in copper
]]
function WarbandNexus:GetWarbandBankMoney()
    if C_Bank and C_Bank.FetchDepositedMoney then
        return C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
    end
    return 0
end

--[[
    Sort the Warband bank
    Uses Blizzard's built-in sorting function (ToS-compliant)
]]
function WarbandNexus:SortWarbandBank()
    if not self:IsWarbandBankOpen() then
        self:Print(L["BANK_NOT_OPEN"])
        return false
    end
    
    -- Use C_Container API for sorting
    if C_Container and C_Container.SortAccountBankBags then
        C_Container.SortAccountBankBags()
        return true
    else
        self:Print(L["ERROR_API_UNAVAILABLE"])
        return false
    end
end

--[[
    Find empty slots in Warband bank
    @return table Array of {tabIndex, slotID} for empty slots
]]
function WarbandNexus:FindEmptySlots()
    local emptySlots = {}
    
    if not self:IsWarbandBankOpen() then
        return emptySlots
    end
    
    for tabIndex, bagID in ipairs(ns.WARBAND_BAGS) do
        -- Skip ignored tabs
        if not self.db.profile.ignoredTabs[tabIndex] then
            local numSlots = self:GetBagSize(bagID)
            
            for slotID = 1, numSlots do
                local itemInfo = self:GetContainerItemInfo(bagID, slotID)
                
                if not itemInfo or not itemInfo.itemID then
                    tinsert(emptySlots, {
                        tabIndex = tabIndex,
                        bagID = bagID,
                        slotID = slotID,
                    })
                end
            end
        end
    end
    
    return emptySlots
end

--[[
    Get deposit queue summary
    @return table Summary information
]]
function WarbandNexus:GetDepositQueueSummary()
    local queue = self.db.char.depositQueue
    local summary = {
        itemCount = #queue,
        totalStacks = 0,
        byQuality = {},
    }
    
    -- Initialize quality counts
    for i = 0, 8 do
        summary.byQuality[i] = 0
    end
    
    for _, item in ipairs(queue) do
        summary.totalStacks = summary.totalStacks + (item.count or 1)
        
        local quality = item.quality or 0
        summary.byQuality[quality] = (summary.byQuality[quality] or 0) + 1
    end
    
    return summary
end

--[[
    Initialize Banker module and offline caching
]]
function WarbandNexus:InitializeBanker()
    -- Register bank events
    self:RegisterEvent("BANKFRAME_OPENED", function()
        -- Create snapshot when bank opens
        C_Timer.After(1, function() -- Delay to ensure data is loaded
            if self:IsWarbandBankOpen() then
                self:SnapshotWarbandBank()
            end
        end)
    end)
    
    self:RegisterEvent("BANKFRAME_CLOSED", function()
        -- Final snapshot when bank closes
        if self.db.global.warbandBank then
            self:SnapshotWarbandBank()
        end
    end)
    
    -- Load cached snapshot on login
    if self.db.global.warbandData and self.db.global.warbandData.bank then
        warbandBankSnapshot = self.db.global.warbandData.bank
        snapshotTimestamp = self.db.global.warbandData.bank.lastSnapshot or 0
        
        local age = self:GetSnapshotAge()
        if age > 0 then
            self:Debug("Loaded Warband Bank snapshot (" .. self:GetSnapshotAgeString() .. ")")
        end
    end
end

