--[[
    Warband Nexus - API Wrapper Module
    Abstraction layer for WoW API calls
    
    Features:
    - Protect against API changes across patches
    - Fallback to legacy APIs when modern ones unavailable
    - Consistent error handling
    - Performance optimized (cached API checks)
    
    Usage:
    Instead of: C_Container.GetContainerNumSlots(bagID)
    Use:        WarbandNexus:API_GetBagSize(bagID)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- API AVAILABILITY CACHE
-- ============================================================================

-- Cache which APIs are available (checked once, not every call)
local apiAvailable = {
    container = nil,      -- C_Container API
    item = nil,           -- C_Item API
    bank = nil,           -- C_Bank API
    currencyInfo = nil,   -- C_CurrencyInfo API
    weeklyRewards = nil,  -- C_WeeklyRewards API
    mythicPlus = nil,     -- C_MythicPlus API
    mountJournal = nil,   -- C_MountJournal API
    petJournal = nil,     -- C_PetJournal API
    toyBox = nil,         -- C_ToyBox API
}

--[[
    Check API availability (called once on load)
]]
local function CheckAPIAvailability()
    apiAvailable.container = (C_Container ~= nil)
    apiAvailable.item = (C_Item ~= nil)
    apiAvailable.bank = (C_Bank ~= nil)
    apiAvailable.currencyInfo = (C_CurrencyInfo ~= nil)
    apiAvailable.weeklyRewards = (C_WeeklyRewards ~= nil)
    apiAvailable.mythicPlus = (C_MythicPlus ~= nil)
    apiAvailable.mountJournal = (C_MountJournal ~= nil)
    apiAvailable.petJournal = (C_PetJournal ~= nil)
    apiAvailable.toyBox = (C_ToyBox ~= nil)
end

-- ============================================================================
-- CONTAINER API WRAPPERS
-- ============================================================================

--[[
    Get number of slots in a bag
    @param bagID number - Bag ID
    @return number - Number of slots (0 if bag doesn't exist)
]]
function WarbandNexus:API_GetBagSize(bagID)
    if apiAvailable.container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagID) or 0
    elseif GetContainerNumSlots then
        return GetContainerNumSlots(bagID) or 0
    end
    return 0
end

--[[
    Get item info from a bag slot
    @param bagID number - Bag ID
    @param slotID number - Slot ID
    @return table|nil - Item info table or nil
]]
function WarbandNexus:API_GetContainerItemInfo(bagID, slotID)
    if apiAvailable.container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bagID, slotID)
    elseif GetContainerItemInfo then
        -- Legacy API returns different format, need to convert
        local icon, count, locked, quality, readable, lootable, link, 
              isFiltered, noValue, itemID = GetContainerItemInfo(bagID, slotID)
        
        if icon then
            return {
                iconFileID = icon,
                stackCount = count,
                isLocked = locked,
                quality = quality,
                isReadable = readable,
                hasLoot = lootable,
                hyperlink = link,
                isFiltered = isFiltered,
                hasNoValue = noValue,
                itemID = itemID,
            }
        end
    end
    return nil
end

--[[
    Get item ID from bag slot
    @param bagID number - Bag ID
    @param slotID number - Slot ID
    @return number|nil - Item ID or nil
]]
function WarbandNexus:API_GetContainerItemID(bagID, slotID)
    if apiAvailable.container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bagID, slotID)
    elseif GetContainerItemID then
        return GetContainerItemID(bagID, slotID)
    else
        -- Fallback: parse from item link
        local itemInfo = self:API_GetContainerItemInfo(bagID, slotID)
        if itemInfo and itemInfo.hyperlink then
            return tonumber(itemInfo.hyperlink:match("item:(%d+)"))
        end
    end
    return nil
end

--[[
    Sort bags
    @param bagID number - Optional bag ID to sort (nil = all bags)
]]
function WarbandNexus:API_SortBags(bagID)
    if apiAvailable.container and C_Container.SortBags then
        C_Container.SortBags()
    elseif SortBags then
        SortBags()
    end
end

--[[
    Sort bank bags
]]
function WarbandNexus:API_SortBankBags()
    if apiAvailable.container and C_Container.SortBankBags then
        C_Container.SortBankBags()
    elseif SortBankBags then
        SortBankBags()
    end
end

--[[
    Pickup item from container (TWW API)
    @param bagID number - Bag ID
    @param slotID number - Slot ID
    @return boolean - Success status
]]
function WarbandNexus:API_PickupItem(bagID, slotID)
    -- CRITICAL: Protected function, check combat
    if InCombatLockdown() then
        if self and self.Print then
            self:Print("|cffff6600Cannot move items during combat.|r")
        end
        return false
    end
    
    if apiAvailable.container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bagID, slotID)
    elseif PickupContainerItem then
        PickupContainerItem(bagID, slotID)
    end
    return true
end

--[[
    Get number of free slots in a bag (TWW API)
    @param bagID number - Bag ID
    @return number - Number of free slots
]]
function WarbandNexus:API_GetFreeBagSlots(bagID)
    if apiAvailable.container and C_Container.GetContainerNumFreeSlots then
        return C_Container.GetContainerNumFreeSlots(bagID) or 0
    elseif GetContainerNumFreeSlots then
        return GetContainerNumFreeSlots(bagID) or 0
    end
    return 0
end

--[[
    Use item from container (TWW API)
    @param bagID number - Bag ID
    @param slotID number - Slot ID
    @return boolean - Success status
]]
function WarbandNexus:API_UseItem(bagID, slotID)
    -- CRITICAL: Protected function, check combat
    if InCombatLockdown() then
        if self and self.Print then
            self:Print("|cffff6600Cannot use items during combat.|r")
        end
        return false
    end
    
    if apiAvailable.container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bagID, slotID)
    elseif UseContainerItem then
        UseContainerItem(bagID, slotID)
    end
    return true
end

-- ============================================================================
-- ITEM API WRAPPERS
-- ============================================================================

--[[
    Get item info
    @param itemID number|string - Item ID or item link
    @return ... - Item info (name, link, quality, ilvl, minLevel, type, subType, stackSize, equipLoc, icon, sellPrice, classID, subclassID, bindType, expacID, setID, isCraftingReagent)
]]
function WarbandNexus:API_GetItemInfo(itemID)
    if apiAvailable.item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemID)
    elseif GetItemInfo then
        return GetItemInfo(itemID)
    end
    return nil
end

--[[
    Get item info instant (synchronous, no async loading)
    @param itemID number - Item ID
    @return number, number, number, string - itemID, itemType, itemSubType, equipLoc
]]
function WarbandNexus:API_GetItemInfoInstant(itemID)
    if apiAvailable.item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(itemID)
    elseif GetItemInfoInstant then
        return GetItemInfoInstant(itemID)
    end
    return nil
end

--[[
    Get item name
    @param itemID number|string - Item ID or item link
    @return string|nil - Item name
]]
function WarbandNexus:API_GetItemName(itemID)
    local name = select(1, self:API_GetItemInfo(itemID))
    return name
end

--[[
    Get item quality
    @param itemID number|string - Item ID or item link
    @return number|nil - Quality (0-7)
]]
function WarbandNexus:API_GetItemQuality(itemID)
    local quality = select(3, self:API_GetItemInfo(itemID))
    return quality
end

-- ============================================================================
-- BANK API WRAPPERS
-- ============================================================================

--[[
    Check if bank is open
    @param bankType number - Optional bank type (Enum.BankType.Account or Enum.BankType.Character)
    @return boolean - True if bank is open
]]
function WarbandNexus:API_IsBankOpen(bankType)
    if apiAvailable.bank and C_Bank.IsBankOpen then
        if bankType then
            return C_Bank.IsBankOpen(bankType)
        else
            -- Check if any bank is open
            return C_Bank.IsBankOpen()
        end
    else
        -- Fallback: Check frame visibility
        return BankFrame and BankFrame:IsShown()
    end
end

--[[
    Get number of purchased bank slots
    @return number - Number of purchased slots
]]
function WarbandNexus:API_GetNumBankSlots()
    if GetNumBankSlots then
        return GetNumBankSlots()
    end
    return 0
end

--[[
    Check if bank can be used (TWW C_Bank API)
    @param bankType string - "account" for Warband, "character" for Personal, nil for any (ignored in TWW)
    @return boolean - True if bank is accessible
]]
function WarbandNexus:API_CanUseBank(bankType)
    -- TWW: C_Bank.CanUseBank() takes NO parameters, just checks if bank UI is open
    if C_Bank and C_Bank.CanUseBank then
        local success, result = pcall(C_Bank.CanUseBank)
        if success then
            return result
        end
    end
    
    -- Fallback: Check if BankFrame is shown
    if BankFrame and BankFrame:IsShown() then
        return true
    end
    
    -- Last resort: assume true if bank is flagged as open
    return true
end

--[[
    Check if player can deposit money (TWW C_Bank API)
    @return boolean - True if can deposit
]]
function WarbandNexus:API_CanDepositMoney()
    if apiAvailable.bank and C_Bank.CanDepositMoney then
        return C_Bank.CanDepositMoney()
    end
    return true
end

--[[
    Check if player can withdraw money (TWW C_Bank API)
    @return boolean - True if can withdraw
]]
function WarbandNexus:API_CanWithdrawMoney()
    if apiAvailable.bank and C_Bank.CanWithdrawMoney then
        return C_Bank.CanWithdrawMoney()
    end
    return true
end

--[[
    Auto-deposit item to bank (TWW C_Bank API)
    @param bagID number - Bag ID
    @param slotID number - Slot ID
    @return boolean - True if successful
]]
function WarbandNexus:API_AutoBankItem(bagID, slotID)
    if apiAvailable.bank and C_Bank.AutoBankItem then
        C_Bank.AutoBankItem(bagID, slotID)
        return true
    end
    return false
end

-- ============================================================================
-- MONEY/GOLD API WRAPPERS
-- ============================================================================

--[[
    Get player's current money
    @return number - Money in copper
]]
function WarbandNexus:API_GetMoney()
    if GetMoney then
        return GetMoney()
    end
    return 0
end

--[[
    Format money as colored string with icons
    @param amount number - Money in copper
    @return string - Formatted string (e.g., "12g 34s 56c")
]]
function WarbandNexus:API_FormatMoney(amount)
    if GetCoinTextureString then
        return GetCoinTextureString(amount)
    elseif GetMoneyString then
        return GetMoneyString(amount)
    else
        -- Fallback: Manual formatting
        local gold = math.floor(amount / 10000)
        local silver = math.floor((amount % 10000) / 100)
        local copper = amount % 100
        
        local str = ""
        if gold > 0 then
            str = str .. gold .. "g "
        end
        if silver > 0 or gold > 0 then
            str = str .. silver .. "s "
        end
        str = str .. copper .. "c"
        
        return str
    end
end

-- ============================================================================
-- PVE API WRAPPERS
-- ============================================================================

--[[
    Get weekly reward activities (Great Vault)
    @return table|nil - Array of activity data
]]
function WarbandNexus:API_GetWeeklyRewards()
    if apiAvailable.weeklyRewards and C_WeeklyRewards.GetActivities then
        return C_WeeklyRewards.GetActivities()
    end
    return nil
end

--[[
    Get Mythic+ run history
    @param includeIncomplete boolean - Include incomplete runs
    @param includePreviousWeeks boolean - Include previous weeks
    @return table|nil - Array of run data
]]
function WarbandNexus:API_GetMythicPlusRuns(includeIncomplete, includePreviousWeeks)
    if apiAvailable.mythicPlus and C_MythicPlus.GetRunHistory then
        return C_MythicPlus.GetRunHistory(includeIncomplete, includePreviousWeeks)
    end
    return nil
end

--[[
    Get number of saved instances (raid lockouts)
    @return number - Number of saved instances
]]
function WarbandNexus:API_GetNumSavedInstances()
    if GetNumSavedInstances then
        return GetNumSavedInstances()
    end
    return 0
end

--[[
    Get saved instance info
    @param index number - Instance index (1-based)
    @return ... - Instance data
]]
function WarbandNexus:API_GetSavedInstanceInfo(index)
    if GetSavedInstanceInfo then
        return GetSavedInstanceInfo(index)
    end
    return nil
end

-- ============================================================================
-- COLLECTION API WRAPPERS
-- ============================================================================

--[[
    Get number of mounts
    @return number - Total mounts
]]
function WarbandNexus:API_GetNumMounts()
    if apiAvailable.mountJournal and C_MountJournal.GetNumMounts then
        return C_MountJournal.GetNumMounts() or 0
    end
    return 0
end

--[[
    Get number of pets
    @return number - Total pets
]]
function WarbandNexus:API_GetNumPets()
    if apiAvailable.petJournal and C_PetJournal.GetNumPets then
        return C_PetJournal.GetNumPets() or 0
    end
    return 0
end

--[[
    Get number of toys
    @return number - Total toys
]]
function WarbandNexus:API_GetNumToys()
    if apiAvailable.toyBox and C_ToyBox.GetNumToys then
        return C_ToyBox.GetNumToys() or 0
    end
    return 0
end

--[[
    Get total achievement points
    @return number - Achievement points
]]
function WarbandNexus:API_GetAchievementPoints()
    if GetTotalAchievementPoints then
        return GetTotalAchievementPoints() or 0
    end
    return 0
end

-- ============================================================================
-- TIME/DATE API WRAPPERS
-- ============================================================================

--[[
    Get server time
    @return number - Server timestamp
]]
function WarbandNexus:API_GetServerTime()
    if GetServerTime then
        return GetServerTime()
    end
    return time()
end

--[[
    Get seconds until weekly reset
    @return number - Seconds until reset
]]
function WarbandNexus:API_GetSecondsUntilWeeklyReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        return C_DateAndTime.GetSecondsUntilWeeklyReset()
    end
    return 0
end

-- ============================================================================
-- TOOLTIP API WRAPPERS
-- ============================================================================

--[[
    Set tooltip to item
    @param tooltip frame - Tooltip frame
    @param itemLink string - Item link
]]
function WarbandNexus:API_SetTooltipItem(tooltip, itemLink)
    if tooltip and tooltip.SetHyperlink then
        tooltip:SetHyperlink(itemLink)
    elseif tooltip and tooltip.SetItemByID then
        local itemID = tonumber(itemLink:match("item:(%d+)"))
        if itemID then
            tooltip:SetItemByID(itemID)
        end
    end
end

-- ============================================================================
-- UNIT API WRAPPERS
-- ============================================================================

--[[
    Get unit name
    @param unit string - Unit ID
    @return string, string - Name, realm
]]
function WarbandNexus:API_GetUnitName(unit)
    if UnitName then
        return UnitName(unit)
    end
    return "Unknown", "Unknown"
end

--[[
    Get unit class
    @param unit string - Unit ID
    @return string, string, number - className, classFile, classID
]]
function WarbandNexus:API_GetUnitClass(unit)
    if UnitClass then
        return UnitClass(unit)
    end
    return "Unknown", "UNKNOWN", 0
end

--[[
    Get unit level
    @param unit string - Unit ID
    @return number - Level
]]
function WarbandNexus:API_GetUnitLevel(unit)
    if UnitLevel then
        return UnitLevel(unit)
    end
    return 0
end

--[[
    Get unit race
    @param unit string - Unit ID
    @return string, string - localizedRace, englishRace
]]
function WarbandNexus:API_GetUnitRace(unit)
    if UnitRace then
        return UnitRace(unit)
    end
    return "Unknown", "Unknown"
end

--[[
    Get unit faction
    @param unit string - Unit ID
    @return string - Faction (Alliance, Horde, Neutral)
]]
function WarbandNexus:API_GetUnitFaction(unit)
    if UnitFactionGroup then
        return UnitFactionGroup(unit)
    end
    return "Neutral"
end

-- ============================================================================
-- REALM API WRAPPERS
-- ============================================================================

--[[
    Get realm name
    @return string - Realm name
]]
function WarbandNexus:API_GetRealmName()
    if GetRealmName then
        return GetRealmName()
    end
    return "Unknown"
end

--[[
    Get normalized realm name (removes spaces, special chars)
    @return string - Normalized realm name
]]
function WarbandNexus:API_GetNormalizedRealmName()
    if GetNormalizedRealmName then
        return GetNormalizedRealmName()
    else
        local realm = self:API_GetRealmName()
        return realm:gsub("[%s%-']", "")
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--[[
    Initialize API wrapper
    Check which APIs are available
]]
function WarbandNexus:InitializeAPIWrapper()
    CheckAPIAvailability()
    
    -- API Wrapper initialized
end

-- ============================================================================
-- API COMPATIBILITY REPORT
-- ============================================================================

--[[
    Get API compatibility report
    @return table - Report of which APIs are available
]]
function WarbandNexus:GetAPICompatibilityReport()
    return {
        C_Container = apiAvailable.container,
        C_Item = apiAvailable.item,
        C_Bank = apiAvailable.bank,
        C_CurrencyInfo = apiAvailable.currencyInfo,
        C_WeeklyRewards = apiAvailable.weeklyRewards,
        C_MythicPlus = apiAvailable.mythicPlus,
        C_MountJournal = apiAvailable.mountJournal,
        C_PetJournal = apiAvailable.petJournal,
        C_ToyBox = apiAvailable.toyBox,
    }
end

--[[
    Print API compatibility report
]]
function WarbandNexus:PrintAPIReport()
    local report = self:GetAPICompatibilityReport()
    
    self:Print("===== API Compatibility Report =====")
    for api, available in pairs(report) do
        local status = available and "|cff00ff00Available|r" or "|cffff0000Missing|r"
        self:Print(string.format("%s: %s", api, status))
    end
end

-- Export API availability for debugging
ns.APIAvailable = apiAvailable
