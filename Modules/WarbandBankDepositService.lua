--[[
    Warband Nexus - Warband Bank & Reagent Deposit Service
    Automated and selective deposit of crafting reagents and token items
    into the Warband Bank (Account Bank) or Personal Reagent Bank.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L
local E = ns.Constants.EVENTS

-- Throttling & Cooldowns
local lastActionTime = 0
local ACTION_COOLDOWN = 2.0

-- INVENTORY BAGS (Backpack 0, Bags 1-4, Reagent Bag 5)
local INVENTORY_BAGS = { 0, 1, 2, 3, 4, 5 }

-- Known non-panel currency / token items that live in bags
local KNOWN_CURRENCY_TOKENS = {
    [137642] = true, -- Mark of Honor
    [163036] = true, -- Polished Pet Charm
    [116415] = true, -- Shiny Pet Charm
    [32247]  = true, -- Darkmoon Prize Ticket
}

-- Subclasses under Enum.ItemClass.Tradegoods (7)
local SUBCLASS_TO_CATEGORY = {
    [0]  = "general",
    [1]  = "parts",
    [4]  = "gems",
    [5]  = "cloth",
    [6]  = "leather",
    [7]  = "mining",
    [8]  = "cooking",
    [9]  = "herbs",
    [10] = "elemental",
    [12] = "enchanting",
    [16] = "inscription",
}

local DEFAULT_CATEGORIES = {
    herbs       = true,
    mining      = true,
    cloth       = true,
    leather     = true,
    enchanting  = true,
    cooking     = true,
    inscription = true,
    gems        = true,
    parts       = true,
    elemental   = true,
    general     = true,
    tokens      = true,
    warbound    = true,
}

local DEFAULT_SETTINGS = {
    enabled           = true,
    autoDepositOnOpen = false,
    destination       = "warband", -- "warband" (Account Bank) or "reagent" (Personal Reagent Bank)
    categories        = DEFAULT_CATEGORIES,
}

-- Resolve settings (per-character override -> profile fallback)
local function GetEffectiveDepositSettings()
    if not WarbandNexus or not WarbandNexus.db then return DEFAULT_SETTINGS end
    local charSettings = WarbandNexus.db.char and WarbandNexus.db.char.reagentDeposit
    if charSettings and charSettings.perCharacter then
        return charSettings
    end
    local profSettings = WarbandNexus.db.profile and WarbandNexus.db.profile.reagentDeposit
    if profSettings then
        return profSettings
    end
    return DEFAULT_SETTINGS
end


---Determine which category an item belongs to
local function GetItemReagentCategory(itemID)
    if not itemID then return nil end
    if KNOWN_CURRENCY_TOKENS[itemID] then
        return "tokens"
    end
    if not C_Item or not C_Item.GetItemInfoInstant then return nil end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if classID == Enum.ItemClass.Tradegoods then
        return SUBCLASS_TO_CATEGORY[subClassID] or "general"
    elseif classID == Enum.ItemClass.Gem then
        return "gems"
    elseif classID == Enum.ItemClass.ItemEnhancement then
        return "enchanting"
    end
    -- Check isCraftingReagent via GetItemInfo if available
    if C_Item.GetItemInfo then
        local isReagent = select(17, C_Item.GetItemInfo(itemID))
        if isReagent then
            return "general"
        end
    end
    return nil
end

---Collect items matching enabled categories from player bags
local function CollectDepositItems(bankType, categories)
    local itemsToMove = {}
    if not C_Container or not C_Container.GetContainerNumSlots then return itemsToMove end

    for bi = 1, #INVENTORY_BAGS do
        local bagID = INVENTORY_BAGS[bi]
        local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID and not info.isLocked then
                local cat = GetItemReagentCategory(info.itemID)
                if cat and categories[cat] then
                    local allowed = true
                    if bankType == Enum.BankType.Account and C_Bank and C_Bank.IsItemAllowedInBankType and ItemLocation and ItemLocation.CreateFromBagAndSlot then
                        local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slot)
                        if itemLocation and itemLocation.IsValid and itemLocation:IsValid() then
                            local ok, res = pcall(C_Bank.IsItemAllowedInBankType, Enum.BankType.Account, itemLocation)
                            if ok and res == false then
                                allowed = false
                            end
                        end
                    end
                    if allowed then
                        itemsToMove[#itemsToMove + 1] = {
                            bag = bagID,
                            slot = slot,
                            itemID = info.itemID,
                        }
                    end
                end
            end
        end
    end
    return itemsToMove
end

---Process item deposit queue smoothly with small delays
local function ProcessDepositQueue(queue, bankType, onComplete)
    if not queue or #queue == 0 then
        if onComplete then onComplete(0) end
        return
    end

    local index = 1
    local totalMoved = 0

    local function Step()
        if InCombatLockdown() or not WarbandNexus.bankIsOpen then
            if onComplete then onComplete(totalMoved) end
            return
        end

        local processedInBatch = 0
        while index <= #queue and processedInBatch < 1 do
            local item = queue[index]
            index = index + 1
            if item and C_Container and C_Container.UseContainerItem then
                local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
                if info and info.itemID == item.itemID and not info.isLocked then
                    C_Container.UseContainerItem(item.bag, item.slot, nil, bankType, false)
                    totalMoved = totalMoved + 1
                    processedInBatch = processedInBatch + 1
                end
            end
        end

        if index <= #queue then
            C_Timer.After(0.08, Step)
        else
            if onComplete then onComplete(totalMoved) end
        end
    end

    Step()
end

---Core deposit execution
local function PerformDeposit(isManual)
    if InCombatLockdown() or not WarbandNexus.bankIsOpen then return end

    local now = GetTime()
    if not isManual and (now - lastActionTime) < ACTION_COOLDOWN then
        return
    end

    local settings = GetEffectiveDepositSettings()
    if not settings or not settings.enabled then return end
    if not isManual and not settings.autoDepositOnOpen then return end

    local categories = settings.categories or DEFAULT_CATEGORIES
    local isWarband = (settings.destination ~= "reagent")
    local bankType = isWarband and Enum.BankType.Account or Enum.BankType.Character

    lastActionTime = now

    -- 1. If targeting Warband Bank and Warbound Equipment is enabled, trigger Blizzard's native WuE deposit
    local gearDepositDelay = 0
    if isWarband and categories.warbound and C_Bank and C_Bank.AutoDepositItemsIntoBank then
        pcall(C_Bank.AutoDepositItemsIntoBank, Enum.BankType.Account)
        gearDepositDelay = 0.25
    end

    -- 2. Deposit all selected crafting reagents & token currencies into target bank
    C_Timer.After(gearDepositDelay, function()
        if not WarbandNexus.bankIsOpen then return end
        local items = CollectDepositItems(bankType, categories)
        ProcessDepositQueue(items, bankType)
    end)
end

-- PUBLIC API

function WarbandNexus:TriggerReagentDeposit(isManual)
    C_Timer.After(0.2, function()
        if not WarbandNexus.bankIsOpen then return end
        PerformDeposit(isManual)
    end)
end

function WarbandNexus:GetEffectiveReagentDepositSettings()
    return GetEffectiveDepositSettings()
end

function WarbandNexus:GetDefaultReagentCategories()
    return DEFAULT_CATEGORIES
end

function WarbandNexus:WN_REAGENT_DEPOSIT_CHANGED()
    lastActionTime = 0
    if WarbandNexus.bankIsOpen then
        local s = GetEffectiveDepositSettings()
        if s and s.enabled and s.autoDepositOnOpen then
            PerformDeposit(false)
        end
    end
end

function WarbandNexus:InitializeReagentDepositService()
    self:RegisterMessage(E.REAGENT_DEPOSIT_CHANGED)
end
