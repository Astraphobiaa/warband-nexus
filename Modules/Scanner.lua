local WarbandNexus = LibStub("AceAddon-3.0"):GetAddon("WarbandNexus")
local Scanner = WarbandNexus:NewModule("Scanner", "AceEvent-3.0")

function Scanner:OnEnable()
    -- Scanner enabled
end

-- Helper to get item info safely
local function GetItemData(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    
    return {
        id = info.itemID,
        count = info.stackCount,
        link = info.hyperlink,
        icon = info.iconFileID,
        quality = info.quality,
        bag = bag,
        slot = slot
    }
end

-- Scan the Warband Bank (Account Bank)
function Scanner:ScanWarbandBank()
    if not C_Bank.CanUseBank(Enum.BankType.Account) then return end
    
    local items = {}
    -- Warband bank has 5 tabs, usually indexed via Enum.BagIndex.AccountBankTab_1 to _5
    -- However, C_Container uses specific bag IDs for these.
    
    local accountBagIDs = {
        Enum.BagIndex.AccountBankTab_1,
        Enum.BagIndex.AccountBankTab_2,
        Enum.BagIndex.AccountBankTab_3,
        Enum.BagIndex.AccountBankTab_4,
        Enum.BagIndex.AccountBankTab_5
    }
    
    for _, bagID in ipairs(accountBagIDs) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local item = GetItemData(bagID, slot)
            if item then
                table.insert(items, item)
            end
        end
    end
    
    -- Save to DB (wipe old data to prevent ghosts)
    WarbandNexus.db.global.warbandCache = items
    -- WarbandNexus:Print("Warband Bank Scanned: " .. #items .. " items found.")
end

-- Scan Personal Bank and Bags
function Scanner:ScanPersonalBank()
    local items = {}
    
    -- 1. Scan Inventory (Backpack + Bags 1-4)
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local item = GetItemData(bag, slot)
            if item then
                table.insert(items, item)
            end
        end
    end
    
    -- 2. Scan Bank (Generic Bank + Bank Bags)
    -- Bank bag ID is -1, Bank bags are 6-12 (usually)
    if C_Bank.IsOpen() then
        -- Main Bank Window (-1)
        local numSlots = C_Container.GetContainerNumSlots(Enum.BagIndex.Bank)
        for slot = 1, numSlots do
            local item = GetItemData(Enum.BagIndex.Bank, slot)
            if item then
                table.insert(items, item)
            end
        end
        
        -- Bank Bags (Enum.BagIndex.BankBag_1 to _7)
        for i = 1, 7 do
             local bankBagID = Enum.BagIndex["BankBag_"..i]
             if bankBagID then
                 local slots = C_Container.GetContainerNumSlots(bankBagID)
                 for slot = 1, slots do
                     local item = GetItemData(bankBagID, slot)
                     if item then
                         table.insert(items, item)
                     end
                 end
             end
        end
    end
    
    -- Save to character specific DB
    local charName = UnitName("player")
    if not WarbandNexus.db.global.characters[charName] then
        WarbandNexus.db.global.characters[charName] = {}
    end
    
    WarbandNexus.db.global.characters[charName].bank = items
    WarbandNexus.db.global.characters[charName].money = GetMoney()
    
    -- WarbandNexus:Print("Personal Bank/Bags Scanned.")
end

function Scanner:ScanBags()
    -- Just scan bags (0-4)
    -- This is called on BAG_UPDATE mostly
    self:ScanPersonalBank() -- For now, we update the whole character record
end
