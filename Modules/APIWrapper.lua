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
-- GAME VERSION & BUILD INFO
-- ============================================================================

local gameVersion = {
    major = 0,      -- Major version (e.g., 11 for TWW)
    minor = 0,      -- Minor version (e.g., 0)
    patch = 0,      -- Patch version (e.g., 7)
    build = 0,      -- Build number
    versionString = "Unknown",  -- Full version string
}

---Get game version information
---@return table Game version info
local function GetGameVersion()
    local version, build, date, tocVersion = GetBuildInfo()
    if version then
        gameVersion.versionString = version
        gameVersion.build = tonumber(build) or 0
        
        -- Parse version string (e.g., "11.0.7")
        local major, minor, patch = version:match("(%d+)%.(%d+)%.(%d+)")
        gameVersion.major = tonumber(major) or 0
        gameVersion.minor = tonumber(minor) or 0
        gameVersion.patch = tonumber(patch) or 0
    end
    return gameVersion
end

---Check if game version is at least the specified version
---@param major number Major version
---@param minor number|nil Minor version (defaults to 0)
---@param patch number|nil Patch version (defaults to 0)
---@return boolean True if current version >= specified version
local function IsGameVersionAtLeast(major, minor, patch)
    minor = minor or 0
    patch = patch or 0
    
    if gameVersion.major > major then return true end
    if gameVersion.major < major then return false end
    
    if gameVersion.minor > minor then return true end
    if gameVersion.minor < minor then return false end
    
    return gameVersion.patch >= patch
end

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
    reputation = nil,     -- C_Reputation API
    majorFactions = nil,  -- C_MajorFactions API (Renown)
    dateAndTime = nil,    -- C_DateAndTime API
    challengeMode = nil,  -- C_ChallengeMode API
}

-- API call error tracking (for debugging)
local apiErrors = {}

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
    apiAvailable.reputation = (C_Reputation ~= nil)
    apiAvailable.majorFactions = (C_MajorFactions ~= nil)
    apiAvailable.dateAndTime = (C_DateAndTime ~= nil)
    apiAvailable.challengeMode = (C_ChallengeMode ~= nil)
end

---Log API error (for debugging repeated failures)
---@param apiName string API name (e.g., "C_Container.GetContainerNumSlots")
---@param error string Error message
local function LogAPIError(apiName, error)
    if not apiErrors[apiName] then
        apiErrors[apiName] = {count = 0, lastError = nil, firstSeen = time()}
    end
    apiErrors[apiName].count = apiErrors[apiName].count + 1
    apiErrors[apiName].lastError = error
    apiErrors[apiName].lastSeen = time()
    
    -- Only print first 3 errors to avoid spam
    if apiErrors[apiName].count <= 3 then
        print("|cffffcc00[WN APIWrapper]|r API Error (" .. apiName .. "): " .. tostring(error))
    end
end

---Safe API call with error handling
---@param apiName string API name for logging
---@param func function Function to call
---@param fallback any Fallback value if call fails
---@return any Result or fallback
local function SafeAPICall(apiName, func, fallback)
    local success, result = pcall(func)
    if success then
        return result
    else
        LogAPIError(apiName, result)
        return fallback
    end
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

-- REMOVED: API_CanDepositMoney() and API_CanWithdrawMoney() - Unused functions

-- ============================================================================
-- MONEY/GOLD API WRAPPERS
-- ============================================================================

--[[
    Get player's current money
    @return number - Money in copper
]]
-- REMOVED: API_GetMoney() - Unused function, GetMoney() is directly available

--[[
    Format money as colored string with icons
    @param amount number - Money in copper
    @return string - Formatted string (e.g., "12g 34s 56c")
]]
function WarbandNexus:API_FormatMoney(amount)
    -- Validate and sanitize input to prevent integer overflow
    amount = tonumber(amount) or 0
    if amount < 0 then amount = 0 end
    
    if GetCoinTextureString then
        local success, result = pcall(GetCoinTextureString, amount)
        if success and result then
            return result
        end
        -- If GetCoinTextureString fails, fall through to alternative
    end
    
    if GetMoneyString then
        local success, result = pcall(GetMoneyString, amount)
        if success and result then
            return result
        end
    end
    
    -- Fallback: Manual formatting (safe for all values)
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = math.floor(amount % 100)
    
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

-- REMOVED: API_SetTooltipItem() - Unused function, tooltip:SetHyperlink() is directly available

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
    Check which APIs are available and game version
]]
function WarbandNexus:InitializeAPIWrapper()
    -- Get game version info
    GetGameVersion()
    
    -- Check API availability
    CheckAPIAvailability()
    
    -- APIWrapper initialized (verbose logging removed)
    
    -- API Wrapper initialized
end

--[[
    Get game version info
    @return table Game version info
]]
function WarbandNexus:GetGameVersion()
    return gameVersion
end

--[[
    Check if game version is at least specified version
    @param major number Major version
    @param minor number|nil Minor version (defaults to 0)
    @param patch number|nil Patch version (defaults to 0)
    @return boolean True if current version >= specified version
]]
function WarbandNexus:IsGameVersionAtLeast(major, minor, patch)
    return IsGameVersionAtLeast(major, minor, patch)
end

--[[
    Get API error log (for debugging)
    @return table API errors
]]
function WarbandNexus:GetAPIErrors()
    return apiErrors
end

--[[
    Clear API error log
]]
function WarbandNexus:ClearAPIErrors()
    apiErrors = {}
    print("|cff00ff00[WN APIWrapper]|r API error log cleared")
end

--[[
    Print API error report
]]
function WarbandNexus:PrintAPIErrorReport()
    local errorCount = 0
    for _ in pairs(apiErrors) do errorCount = errorCount + 1 end
    
    if errorCount == 0 then
        self:Print("No API errors logged")
        return
    end
    
    self:Print(string.format("===== API Error Report (%d APIs) =====", errorCount))
    for apiName, data in pairs(apiErrors) do
        self:Print(string.format("%s: %d errors (last: %s)", 
            apiName, data.count, data.lastError or "unknown"))
    end
end

-- ============================================================================
-- SCREEN & UI SCALE API WRAPPERS
-- ============================================================================

--[[
    Get screen dimensions and UI scale
    @return table {width, height, scale, category}
]]
function WarbandNexus:API_GetScreenInfo()
    local width = UIParent:GetWidth() or 1920
    local height = UIParent:GetHeight() or 1080
    local scale = UIParent:GetEffectiveScale() or 1.0
    
    -- Categorize screen size
    local category = "normal"
    if width < 1600 then
        category = "small"
    elseif width >= 3840 then
        category = "xlarge"
    elseif width >= 2560 then
        category = "large"
    end
    
    return {
        width = width,
        height = height,
        scale = scale,
        category = category,
    }
end

--[[
    Calculate optimal window dimensions based on screen size
    @param contentMinWidth number - Minimum width required for content
    @param contentMinHeight number - Minimum height required for content
    @return number, number, number, number - Optimal width, height, max width, max height
]]
function WarbandNexus:API_CalculateOptimalWindowSize(contentMinWidth, contentMinHeight)
    local screen = self:API_GetScreenInfo()
    
    -- Default size: 50% width, 60% height (comfortable for most content)
    local defaultWidth = math.floor(screen.width * 0.50)
    local defaultHeight = math.floor(screen.height * 0.60)
    
    -- Maximum size: 75% width, 80% height (leave space around window)
    local maxWidth = math.floor(screen.width * 0.75)
    local maxHeight = math.floor(screen.height * 0.80)
    
    -- Apply constraints
    local optimalWidth = math.max(contentMinWidth, math.min(defaultWidth, maxWidth))
    local optimalHeight = math.max(contentMinHeight, math.min(defaultHeight, maxHeight))
    
    return optimalWidth, optimalHeight, maxWidth, maxHeight
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
        gameVersion = gameVersion.versionString,
        gameBuild = gameVersion.build,
        C_Container = apiAvailable.container,
        C_Item = apiAvailable.item,
        C_Bank = apiAvailable.bank,
        C_CurrencyInfo = apiAvailable.currencyInfo,
        C_WeeklyRewards = apiAvailable.weeklyRewards,
        C_MythicPlus = apiAvailable.mythicPlus,
        C_MountJournal = apiAvailable.mountJournal,
        C_PetJournal = apiAvailable.petJournal,
        C_ToyBox = apiAvailable.toyBox,
        C_Reputation = apiAvailable.reputation,
        C_MajorFactions = apiAvailable.majorFactions,
        C_DateAndTime = apiAvailable.dateAndTime,
        C_ChallengeMode = apiAvailable.challengeMode,
    }
end

--[[
    Print API compatibility report
]]
function WarbandNexus:PrintAPIReport()
    local report = self:GetAPICompatibilityReport()
    
    self:Print("===== API Compatibility Report =====")
    self:Print(string.format("Game Version: %s (Build %d)", report.gameVersion, report.gameBuild))
    self:Print("─────────────────────────────────")
    
    for api, available in pairs(report) do
        if api ~= "gameVersion" and api ~= "gameBuild" then
            local status = available and "|cff00ff00Available|r" or "|cffff0000Missing|r"
            self:Print(string.format("%s: %s", api, status))
        end
    end
end

-- Export API availability for debugging
ns.APIAvailable = apiAvailable
