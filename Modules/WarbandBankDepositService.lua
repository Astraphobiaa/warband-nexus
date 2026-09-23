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
    ignoreFood        = true,
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

---Check if an item is consumable food or drink (including Warbound hearty feasts/meals)
local function IsFoodItem(itemID, bagID, slot)
    if not itemID then return false end

    -- 1. Check item class and subclass via instant query
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
        -- Enum.ItemClass.Consumable is 0, subclass 5 is Food & Drink
        local consumableClass = (Enum.ItemClass and Enum.ItemClass.Consumable) or 0
        local foodSubclass = (Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.FoodAndDrink) or 5
        if classID == consumableClass and subClassID == foodSubclass then
            return true
        end
    end

    -- 2. Check full GetItemInfo if available (fallback)
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfo, itemID)
        if ok and classID then
            local consumableClass = (Enum.ItemClass and Enum.ItemClass.Consumable) or 0
            local foodSubclass = (Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.FoodAndDrink) or 5
            if classID == consumableClass and subClassID == foodSubclass then
                return true
            end
        end
    end

    -- 3. Check item spell / effect (food buff check)
    if C_Item and C_Item.GetItemSpell then
        local ok, spellName = pcall(C_Item.GetItemSpell, itemID)
        if ok and spellName and not (issecretvalue and issecretvalue(spellName)) and type(spellName) == "string" then
            local lower = spellName:lower()
            if lower:find("food") or lower:find("feast") or lower:find("well fed") or lower:find("eating") then
                return true
            end
        end
    end

    -- 4. Tooltip scan if bag and slot are provided
    if bagID and slot and C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local ok, tipData = pcall(C_TooltipInfo.GetBagItem, bagID, slot)
        if ok and tipData and tipData.lines then
            for i = 1, #tipData.lines do
                local line = tipData.lines[i]
                local lt = line and line.leftText
                if lt and not (issecretvalue and issecretvalue(lt)) and type(lt) == "string" then
                    if lt:find("Well Fed", 1, true) or lt:find("Must remain seated while eating", 1, true) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

---Check if an item is equipment / gear (Weapons, Armor, Shields, Trinkets, Rings, Profession Tools)
local function IsEquipmentItem(itemID)
    if not itemID then return false end
    if not C_Item or not C_Item.GetItemInfoInstant then return false end

    local _, _, _, itemEquipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return false end

    -- Weapons (2), Armor (4), Profession Equipment (19)
    local weaponClass = (Enum.ItemClass and Enum.ItemClass.Weapon) or 2
    local armorClass = (Enum.ItemClass and Enum.ItemClass.Armor) or 4
    local profClass = (Enum.ItemClass and Enum.ItemClass.Profession) or 19

    if classID == weaponClass or classID == armorClass or classID == profClass then
        return true
    end

    -- Valid equip slot (not empty and not INVTYPE_NON_EQUIP)
    if itemEquipLoc and itemEquipLoc ~= "" and itemEquipLoc ~= "INVTYPE_NON_EQUIP" then
        return true
    end

    return false
end

---Check if an item is Warbound Gear (WuE equipment allowed in Warband Bank)
local function IsWarboundGearItem(bagID, slot, itemID)
    if not bagID or not slot or not itemID then return false end

    -- 1. Must be equipment (Armor, Weapons, Trinkets, Rings, Shields, Cloaks, Profession Tools)
    if not IsEquipmentItem(itemID) then
        return false
    end

    -- 2. Must NOT be food or consumable
    if IsFoodItem(itemID, bagID, slot) then
        return false
    end

    -- 3. Must NOT be part of a saved player equipment set
    if C_Container and C_Container.GetContainerItemEquipmentSetInfo then
        local ok, inSet = pcall(C_Container.GetContainerItemEquipmentSetInfo, bagID, slot)
        if ok and inSet then
            return false
        end
    end

    -- 4. Must be allowed in Account Bank (not soulbound to current character)
    if C_Bank and C_Bank.IsItemAllowedInBankType and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slot)
        if itemLocation and itemLocation.IsValid and itemLocation:IsValid() then
            local ok, allowed = pcall(C_Bank.IsItemAllowedInBankType, Enum.BankType.Account, itemLocation)
            if not ok or not allowed then
                return false
            end
        end
    end

    -- 5. Check raw bind type from item info
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, _, _, bindType = pcall(C_Item.GetItemInfo, itemID)
        if ok and bindType then
            -- 9 = ITEM_BIND_BNET_UNTIL_EQUIPPED ("Warbound until equipped")
            -- 8 = LE_ITEM_BIND_TO_BNETACCOUNT ("Binds to Battle.net Account")
            if bindType == 9 or bindType == 8 or bindType == (ITEM_BIND_WARBAND or 10) then
                return true
            end
        end
    end

    -- 6. Check tooltip lines for Warbound markers
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local ok, tipData = pcall(C_TooltipInfo.GetBagItem, bagID, slot)
        if ok and tipData and tipData.lines then
            local strWuE = _G.ITEM_ACCOUNTBOUND_UNTIL_EQUIP or "Warbound until equipped"
            local strWB1 = _G.ITEM_BIND_TO_BNETACCOUNT or "Binds to Battle.net Account"
            local strWB2 = _G.ITEM_BIND_TO_ACCOUNT or "Binds to Account"
            local strWB3 = _G.ITEM_BIND_TO_WARBAND or "Binds to Warband"
            local strWB4 = "Warbound"

            for li = 1, #tipData.lines do
                local lt = tipData.lines[li] and tipData.lines[li].leftText
                if lt and not (issecretvalue and issecretvalue(lt)) and type(lt) == "string" then
                    if lt:find(strWuE, 1, true) or lt:find("until equipped", 1, true)
                        or lt:find(strWB3, 1, true) or lt:find(strWB1, 1, true)
                        or lt:find(strWB2, 1, true) or lt:find(strWB4, 1, true) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

---Determine which category an item belongs to
local function GetItemReagentCategory(itemID)
    if not itemID then return nil end
    if KNOWN_CURRENCY_TOKENS[itemID] then
        return "tokens"
    end
    if not C_Item or not C_Item.GetItemInfoInstant then return nil end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return nil end

    -- Finished Consumables (Food, Drinks, Potions, Flasks, Elixirs, Bandages) are NEVER crafting reagents
    local consumableClass = (Enum.ItemClass and Enum.ItemClass.Consumable) or 0
    if classID == consumableClass then
        return nil
    end

    -- Equipment / Gear is NEVER a crafting reagent (handled separately via Warbound Gear)
    if IsEquipmentItem(itemID) then
        return nil
    end

    -- Quest items and Bags / Containers are NEVER crafting reagents
    local questClass = (Enum.ItemClass and Enum.ItemClass.Questitem) or 12
    local containerClass = (Enum.ItemClass and Enum.ItemClass.Container) or 1
    if classID == questClass or classID == containerClass then
        return nil
    end

    if classID == Enum.ItemClass.Tradegoods then
        return SUBCLASS_TO_CATEGORY[subClassID] or "general"
    elseif classID == Enum.ItemClass.Gem then
        return "gems"
    elseif classID == Enum.ItemClass.ItemEnhancement then
        return "enchanting"
    end

    -- Check isCraftingReagent via GetItemInfo if available (only for non-consumable, non-gear items)
    if C_Item.GetItemInfo then
        local isReagent = select(17, C_Item.GetItemInfo(itemID))
        if isReagent then
            return "general"
        end
    end
    return nil
end

---Collect items matching enabled categories from player bags
local function CollectDepositItems(bankType, categories, ignoreFood)
    local itemsToMove = {}
    if not C_Container or not C_Container.GetContainerNumSlots then return itemsToMove end

    local isWarband = (bankType == Enum.BankType.Account)
    local checkWarboundGear = isWarband and categories.warbound

    for bi = 1, #INVENTORY_BAGS do
        local bagID = INVENTORY_BAGS[bi]
        local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID and not info.isLocked then
                -- Food check: food/drink/feasts are fundamentally excluded from reagent & gear deposits
                local isFood = IsFoodItem(info.itemID, bagID, slot)
                if not (ignoreFood and isFood) then
                    local matched = false
                    local cat = GetItemReagentCategory(info.itemID)
                    if cat and categories[cat] then
                        -- Double-check safety: food is never deposited as a reagent
                        if not isFood then
                            matched = true
                        end
                    elseif checkWarboundGear and IsWarboundGearItem(bagID, slot, info.itemID) then
                        matched = true
                    end

                    if matched then
                        local allowed = true
                        if isWarband and C_Bank and C_Bank.IsItemAllowedInBankType and ItemLocation and ItemLocation.CreateFromBagAndSlot then
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
    local ignoreFood = (settings.ignoreFood ~= false)

    lastActionTime = now

    -- Collect all matching reagents, tokens & Warbound Gear according to strict item type rules
    local items = CollectDepositItems(bankType, categories, ignoreFood)
    ProcessDepositQueue(items, bankType)
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
