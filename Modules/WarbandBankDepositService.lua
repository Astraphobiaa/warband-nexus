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

-- Item class / subclass IDs (verified against Blizzard_APIDocumentationGenerated
-- ItemConstantsDocumentation 12.1.0 (69933) and warcraft.wiki.gg/wiki/ItemType, 2026-10-08).
-- classID/subClassID come from C_Item.GetItemInfoInstant, which is locale-independent and
-- works for uncached items, so no tooltip or spell-name heuristics are needed.
local ITEM_CLASS_CONSUMABLE  = (Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local ITEM_CLASS_REAGENT     = (Enum.ItemClass and Enum.ItemClass.Reagent) or 5
local ITEM_CLASS_ENHANCEMENT = (Enum.ItemClass and Enum.ItemClass.ItemEnhancement) or 8
local CONSUMABLE_SUBCLASS_FOOD = (Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Fooddrink) or 5
-- Reagent class (5): only subclass 0 is a crafting reagent; 1 = Keystone, 2 = Context Token
local REAGENT_SUBCLASS_REAGENT = (Enum.ItemReagentSubclass and Enum.ItemReagentSubclass.Reagent) or 0

---Check if an item is food or drink (Consumable > Food & Drink, including Warbound hearty meals)
local function IsFoodItem(itemID)
    if not itemID or not C_Item or not C_Item.GetItemInfoInstant then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    return classID == ITEM_CLASS_CONSUMABLE and subClassID == CONSUMABLE_SUBCLASS_FOOD
end

---Check if an item is a finished consumable or item enhancement (food, potions, flasks, phials,
---weapon oils, sharpening stones, armor kits, augment runes, curios). These are never deposited.
local function IsFinishedConsumableItem(itemID)
    if not itemID or not C_Item or not C_Item.GetItemInfoInstant then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID == ITEM_CLASS_CONSUMABLE or classID == ITEM_CLASS_ENHANCEMENT
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

    -- 3. Must NOT be part of a saved player equipment set
    if C_Container and C_Container.GetContainerItemEquipmentSetInfo then
        local ok, inSet = pcall(C_Container.GetContainerItemEquipmentSetInfo, bagID, slot)
        if ok and inSet then
            return false
        end
    end

    -- 4. Must be allowed in Account Bank (not soulbound to current character)
    local itemLocation
    if ItemLocation and ItemLocation.CreateFromBagAndSlot then
        itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slot)
        if itemLocation and not (itemLocation.IsValid and itemLocation:IsValid()) then
            itemLocation = nil
        end
    end
    if itemLocation and C_Bank and C_Bank.IsItemAllowedInBankType then
        local ok, allowed = pcall(C_Bank.IsItemAllowedInBankType, Enum.BankType.Account, itemLocation)
        if not ok or not allowed then
            return false
        end
    end

    -- 5. Live bind state of this exact item ("Warbound until equipped" and not yet equipped)
    if itemLocation and C_Item and C_Item.IsBoundToAccountUntilEquip then
        local ok, isWuE = pcall(C_Item.IsBoundToAccountUntilEquip, itemLocation)
        if ok and isWuE then
            return true
        end
    end

    -- 6. Template bind type (Enum.ItemBind: 7 ToWoWAccount, 8 ToBnetAccount, 9 ToBnetAccountUntilEquipped)
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = pcall(C_Item.GetItemInfo, itemID)
        if ok and (bindType == 7 or bindType == 8 or bindType == 9) then
            return true
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

    -- Finished Consumables (Food, Drinks, Potions, Flasks, Elixirs, Bandages) and Item Enhancements
    -- (Weapon Oils, Sharpening Stones, Armor Kits, Enchant Scrolls, Augment Runes) are NEVER crafting reagents
    if classID == ITEM_CLASS_CONSUMABLE or classID == ITEM_CLASS_ENHANCEMENT then
        return nil
    end

    -- Reagent class: Keystones and Context Tokens are not crafting reagents
    if classID == ITEM_CLASS_REAGENT and subClassID ~= REAGENT_SUBCLASS_REAGENT then
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
    end

    -- Usable items outside Trade Goods / Gems are finished goods, not reagents. Midnight weapon
    -- oils and whetstones are Miscellaneous > Other (15/4), e.g. Thalassian Mana Oil 259201 and
    -- Thalassian Whetstone 259190 (wago.tools Item DB2, 2026-10-08), so the class check misses them.
    if C_Item.GetItemSpell then
        local okSpell, _, useSpellID = pcall(C_Item.GetItemSpell, itemID)
        if okSpell and useSpellID then
            return nil
        end
    end

    -- Check isCraftingReagent via GetItemInfo if available (only for non-consumable, non-gear items)
    if C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, isReagent = pcall(C_Item.GetItemInfo, itemID)
        if ok and isReagent then
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
                -- Food, potions, flasks, oils and other finished consumables are never deposited.
                -- ignoreFood is kept as an explicit guard; food is already a finished consumable.
                local isFood = IsFoodItem(info.itemID)
                if not (ignoreFood and isFood) and not IsFinishedConsumableItem(info.itemID) then
                    local matched = false
                    local cat = GetItemReagentCategory(info.itemID)
                    if cat and categories[cat] then
                        matched = true
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
