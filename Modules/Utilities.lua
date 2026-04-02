--[[
    Warband Nexus - Utilities
    Common helper functions to eliminate code duplication
]]

local ADDON_NAME, ns = ...

---@class Utilities
local Utilities = {}
ns.Utilities = Utilities

--============================================================================
-- CHARACTER IDENTIFICATION
--============================================================================

--- Split a stored "Name-Realm" key using only the **first** hyphen.
--- Realms may contain hyphens (e.g. Azjol-Nerub); player names do not use `-` in WoW.
--- Greedy patterns like "^(.+)%-(.+)$" mis-parse as Name=Player-Azjol, Realm=Nerub.
---@param charKey string|nil
---@return string|nil namePart Space-stripped name prefix
---@return string|nil realmPart Space-stripped realm suffix (may include hyphens, apostrophes)
function Utilities:SplitCharacterKey(charKey)
    if not charKey or charKey == "" then return nil, nil end
    local name, realm = tostring(charKey):match("^([^-]+)%-(.+)$")
    if not name or not realm then return nil, nil end
    return name:gsub("%s+", ""), realm:gsub("%s+", "")
end

--- Get character key (Name-Realm format, normalized: no spaces).
--- Single source of truth for character identification in DB and services.
--- When realm is omitted, prefers GetNormalizedRealmName() — same as DataService / SaveCurrentCharacterData.
--- Using only GetRealmName() here caused /reload to resolve a different key than SavedVariables on some realms.
---@param name string|nil Player name (defaults to current player)
---@param realm string|nil Realm name (defaults to current realm)
---@return string Character key in "Name-Realm" format (e.g. "Superluminal-TwistingNether")
function Utilities:GetCharacterKey(name, realm)
    name = name or UnitName("player")
    if not realm then
        local norm = GetNormalizedRealmName and GetNormalizedRealmName()
        if type(norm) == "string" and norm ~= "" and not (issecretvalue and issecretvalue(norm)) then
            realm = norm
        else
            realm = GetRealmName and GetRealmName() or ""
        end
    end
    
    -- CRITICAL: Normalize key to prevent duplicates
    -- Remove spaces for consistent matching (e.g. "Twisting Nether" -> "TwistingNether")
    name = name:gsub("%s+", "")
    realm = realm:gsub("%s+", "")
    
    local key = name .. "-" .. realm
    return key
end

--- Resolve any character key to the canonical (normalized) form used everywhere in DB and services.
--- Use this when passing a key from UI or stored data into services (currency, gear, etc.).
---@param charKey string Key from db.characters or UI (may have spaces or old format)
---@return string Canonical key (GetCharacterKey(name, realm))
function Utilities:GetCanonicalCharacterKey(charKey)
    if not charKey or charKey == "" then return charKey end
    local db = ns.WarbandNexus and ns.WarbandNexus.db and ns.WarbandNexus.db.global
    local charData = db and db.characters and db.characters[charKey]
    if type(charData) == "table" and charData.name and charData.realm then
        return self:GetCharacterKey(charData.name, charData.realm)
    end

    -- Legacy fallback: normalize any incoming "Name - Realm" / spaced variants.
    -- First hyphen only — realm may be "Azjol-Nerub" etc.
    local name, realm = self:SplitCharacterKey(tostring(charKey))
    if name and realm then
        return self:GetCharacterKey(name, realm)
    end

    return tostring(charKey):gsub("%s+", "")
end

--- Display-only: pretty-print API/normalized realm (e.g. "TwistingNether" -> "Twisting Nether").
--- Persisted `charData.realm` and keys stay as returned by GetNormalizedRealmName / UnitName — do not rewrite storage.
--- Inserts a space before each uppercase letter that follows a lowercase letter.
---@param realm string Realm name (possibly normalized / spaceless)
---@return string Display-friendly realm name with proper spacing
function Utilities:FormatRealmName(realm)
    if not realm or realm == "" then return "" end
    return realm:gsub("(%l)(%u)", "%1 %2")
end

--============================================================================
-- MODULE CHECKS
--============================================================================

--- Check if a module is enabled in settings
--- Eliminates 20+ duplicate checks across codebase
---@param moduleName string Module name (e.g., "pve", "currencies")
---@return boolean Whether the module is enabled
function Utilities:IsModuleEnabled(moduleName)
    local db = ns.WarbandNexus and ns.WarbandNexus.db
    if not db or not db.profile then return false end
    
    local modules = db.profile.modulesEnabled
    if not modules then return false end
    
    return modules[moduleName] == true
end

--============================================================================
-- MIDNIGHT 12.0 SECRET-VALUE GUARDS
--============================================================================
-- WoW 12.0 (Midnight) can return "secret" values from secure APIs; using them
-- in string ops, comparisons, or as table keys causes ADDON_ACTION_FORBIDDEN.
-- Use these helpers before any such use. issecretvalue is nil pre-12.0.
--============================================================================

local issecretvalue = issecretvalue

--- Safe string for display/indexing. Returns fallback if value is nil or secret.
---@param val any Value that might be a string or secret
---@param fallback string|nil Fallback when secret/nil (default "")
---@return string Safe string to use
function Utilities:SafeString(val, fallback)
    if val == nil then return fallback or "" end
    if issecretvalue and issecretvalue(val) then return fallback or "" end
    return tostring(val)
end

--- Safe number for comparisons/math. Returns fallback if value is secret or not a number.
---@param val any Value that might be a number or secret
---@param fallback number|nil Fallback when secret/invalid (default nil)
---@return number|nil Safe number or fallback
function Utilities:SafeNumber(val, fallback)
    if val == nil then return fallback end
    if issecretvalue and issecretvalue(val) then return fallback end
    local n = tonumber(val)
    return (n ~= nil) and n or fallback
end

--- Safe boolean. Returns fallback if value is secret.
---@param val any Value that might be boolean or secret
---@param fallback boolean|nil Fallback when secret (default false)
---@return boolean
function Utilities:SafeBool(val, fallback)
    if val == nil then return fallback ~= nil and fallback or false end
    if issecretvalue and issecretvalue(val) then return fallback ~= nil and fallback or false end
    return not not val
end

--- Safe UnitGUID. Returns nil if GUID is secret (Midnight instanced content).
---@param unit string Unit token (e.g. "player", "target")
---@return string|nil GUID or nil if secret/unavailable
function Utilities:SafeGuid(unit)
    if not unit then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    return guid
end

--- Whether the current runtime has secret-value API (Midnight 12.0+).
---@return boolean
function Utilities:HasSecretValueAPI()
    return issecretvalue ~= nil
end

--- Check if a value is secret; safe to call (no string/table ops on val).
---@param val any
---@return boolean True if val is a secret value
function Utilities:IsSecretValue(val)
    if val == nil then return false end
    return issecretvalue and issecretvalue(val) or false
end

--============================================================================
-- GOLD/CURRENCY HELPERS
--============================================================================

--- Get character's total copper (calculated from gold/silver/copper breakdown)
--- Prevents SavedVariables 32-bit overflow by using breakdown format
---@param charData table Character data from SavedVariables
---@return number Total copper amount
function Utilities:GetCharTotalCopper(charData)
    if not charData then return 0 end
    
    -- New format: gold/silver/copper breakdown (to avoid 32-bit SavedVariables overflow)
    if charData.gold or charData.silver or charData.copper then
        local gold = charData.gold or 0
        local silver = charData.silver or 0
        local copper = charData.copper or 0
        return (gold * 10000) + (silver * 100) + copper
    end
    
    -- Legacy fallback: old totalCopper field (if migration hasn't run yet)
    if charData.totalCopper then
        return charData.totalCopper
    end
    
    return 0
end

--- Get warband bank's total copper (calculated from gold/silver/copper breakdown)
--- Prevents SavedVariables 32-bit overflow by using breakdown format
---@param addon table|nil The WarbandNexus addon instance (optional)
---@param warbandData table|nil Warband bank data from SavedVariables (optional)
---@return number Total copper amount
function Utilities:GetWarbandBankTotalCopper(addon, warbandData)
    if not warbandData and addon then
        warbandData = addon.db and addon.db.global and addon.db.global.warbandBank
    end
    if not warbandData then return 0 end
    
    -- New format: gold/silver/copper breakdown
    if warbandData.gold or warbandData.silver or warbandData.copper then
        local gold = warbandData.gold or 0
        local silver = warbandData.silver or 0
        local copper = warbandData.copper or 0
        return (gold * 10000) + (silver * 100) + copper
    end
    
    -- Legacy fallback: old totalCopper field
    if warbandData.totalCopper then
        return warbandData.totalCopper
    end
    
    return 0
end

--- Get Warband Bank money from C_Bank API (TWW 11.0+)
--- Simple wrapper for C_Bank.FetchDepositedMoney (read-only)
---@return number Account money in copper
function Utilities:GetWarbandBankMoney()
    -- TWW (11.0+) API for getting warband bank gold
    if C_Bank and C_Bank.FetchDepositedMoney then
        local accountMoney = C_Bank.FetchDepositedMoney(Enum.BankType.Account)
        return accountMoney or 0
    end
    return 0
end

--============================================================================
-- BANK/BAG HELPERS
--============================================================================

--- Check if a bag ID is a Warband bag
--- Uses the global WARBAND_BAGS table from namespace
---@param bagID number The bag ID to check
---@return boolean Whether the bag is a Warband bag
function Utilities:IsWarbandBag(bagID)
    for _, warbandBagID in ipairs(ns.WARBAND_BAGS) do
        if bagID == warbandBagID then
            return true
        end
    end
    return false
end

--- Check if Warband bank is currently open
--- Uses event-based tracking combined with bag access verification
--- NOTE: Requires WarbandNexus addon instance for state tracking
---@param addon table The WarbandNexus addon instance
---@return boolean Whether the Warband bank is open
function Utilities:IsWarbandBankOpen(addon)
    if not addon then return false end
    
    -- Primary method: Use tracked state from BANKFRAME events
    if addon.warbandBankIsOpen then
        return true
    end
    
    -- Secondary method: If bank event flag is set, verify we can access Warband bags
    if addon.bankIsOpen then
        local firstBagID = Enum.BagIndex.AccountBankTab_1
        if firstBagID then
            local numSlots = C_Container.GetContainerNumSlots(firstBagID)
            if numSlots and numSlots > 0 then
                -- We can access Warband bank, update flag
                addon.warbandBankIsOpen = true
                return true
            end
        end
    end
    
    -- Fallback: Direct bag access check (in case events were missed)
    local firstBagID = Enum.BagIndex.AccountBankTab_1
    if firstBagID then
        local numSlots = C_Container.GetContainerNumSlots(firstBagID)
        -- In TWW, purchased Warband Bank tabs have 98 slots
        -- Only return true if we also see the bank is truly accessible
        if numSlots and numSlots > 0 then
            addon.warbandBankIsOpen = true
            addon.bankIsOpen = true
            return true
        end
    end
    
    return false
end

--============================================================================
-- ITEM HELPERS
--============================================================================

--- Get display name for an item (handles caged pets)
--- Caged pets show "Pet Cage" in item name but have the real pet name in tooltip line 3
---@param itemID number The item ID
---@param itemName string The item name from cache
---@param classID number|nil The item class ID (17 = Battle Pet)
---@return string displayName The display name (pet name for caged pets, item name otherwise)
function Utilities:GetItemDisplayName(itemID, itemName, classID)
    -- If this is a caged pet (classID 17), try to get the pet name from tooltip
    if classID == 17 and itemID then
        local petName = self:GetPetNameFromTooltip(itemID)
        if petName then
            return petName
        end
    end
    
    -- Fallback: Use item name
    return itemName or ((ns.L and ns.L["UNKNOWN"]) or UNKNOWN or "Unknown")
end

--- Extract pet name from item tooltip (locale-independent)
--- Used for caged pets where item name is "Pet Cage" but tooltip has the real pet name
---@param itemID number The item ID
---@return string|nil petName The pet's name extracted from tooltip
function Utilities:GetPetNameFromTooltip(itemID)
    if not itemID then
        return nil
    end
    
    -- METHOD 1: Try C_PetJournal API first (most reliable)
    -- GetPetInfoByItemID returns: name, icon, petType, creatureID, sourceText, description,
    --   isWild, canBattle, tradeable, unique, obtainable, displayID, speciesID
    -- First return value is the pet name (string), speciesID is the 13th return.
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local petName = C_PetJournal.GetPetInfoByItemID(itemID)
        if type(petName) == "string" and petName ~= "" then
            return petName
        end
    end
    
    -- METHOD 2: Tooltip parsing (fallback)
    if not C_TooltipInfo then
        return nil
    end
    
    local tooltipData = C_TooltipInfo.GetItemByID(itemID)
    if not tooltipData then
        return nil
    end
    
    -- METHOD 2A: CHECK battlePetName FIELD (TWW 11.0+ feature!)
    -- Surface args to expose all fields
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(tooltipData)
    end
    
    -- Check if battlePetName field exists (TWW API)
    if tooltipData.battlePetName and tooltipData.battlePetName ~= "" then
        return tooltipData.battlePetName
    end
    
    -- METHOD 2B: FALLBACK TO LINE PARSING
    if not tooltipData.lines then
        return nil
    end
    
    -- Known bad patterns to skip
    local knownBadPatterns = {
        "^Battle Pet", "^BattlePet", "^Pet Cage", "^Kampfhaustier", "^Mascotte",
        "^Companion", "^Use:", "^Requires:", "Level %d", 
        "^Poor", "^Common", "^Uncommon", "^Rare", "^Epic", "^Legendary", "^%d+$",
    }
    
    -- Parse tooltip lines for pet name
    for i = 1, math.min(#tooltipData.lines, 8) do
        local line = tooltipData.lines[i]
        if line and line.leftText then
            local text = line.leftText
            
            -- Clean color codes and formatting
            local cleanText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|h", ""):gsub("|H", "")
            cleanText = cleanText:match("^%s*(.-)%s*$") or ""
            
            -- Check if this line is a valid pet name
            if #cleanText >= 3 and #cleanText <= 35 then
                local isBadLine = false
                
                -- Check against known bad patterns
                for _, pattern in ipairs(knownBadPatterns) do
                    if cleanText:match(pattern) then
                        isBadLine = true
                        break
                    end
                end
                
                -- Additional checks: contains ":" or starts with digit
                if not isBadLine then
                    if cleanText:match(":") or cleanText:match("^%d") then
                        isBadLine = true
                    end
                end
                
                if not isBadLine then
                    return cleanText
                end
            end
        end
    end

    return nil
end

--============================================================================
-- BAG UTILITIES
--============================================================================

-- GetBagFingerprint: REMOVED — Dead code, never called from any module.
-- ItemsCacheService uses hash-based change detection (GenerateItemHash) instead.
-- This function was iterating all bags 0-4 with GetContainerNumSlots + GetContainerItemInfo
-- per slot (~100+ API calls) and was redundant with the hash system.

--============================================================================
-- TIME FORMATTING
--============================================================================

--- Format time remaining until a given timestamp
--- @param resetTime number Unix timestamp of reset time
--- @return string Formatted time string (e.g., "2d 5h", "3h 45m", "30m")
function Utilities:FormatTimeUntilReset(resetTime)
    local diff = (resetTime or 0) - time()
    return self:FormatTimeCompact(diff)
end

--============================================================================
-- TIME FORMATTING
--============================================================================

---Format a number of seconds into a human-readable compact time string
---@param seconds number Seconds remaining
---@return string Formatted time string (e.g., "2d 5h", "3h 45m", "30m", "Now")
function Utilities:FormatTimeCompact(seconds)
    if not seconds or seconds <= 0 then return "Now" end
    
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
end

---Format a number of seconds into a human-readable played time string
---@param seconds number Total seconds played
---@return string Formatted time string (e.g., "363 Days 16 Hours 55 Minutes")
function Utilities:FormatPlayedTime(seconds)
    local L = ns.L
    local dayS   = (L and L["PLAYED_DAYS"])    or "Days"
    local dayL    = (L and L["PLAYED_DAY"])     or "Day"
    local hourS   = (L and L["PLAYED_HOURS"])   or "Hours"
    local hourL   = (L and L["PLAYED_HOUR"])    or "Hour"
    local minuteS = (L and L["PLAYED_MINUTES"]) or "Minutes"
    local minuteL = (L and L["PLAYED_MINUTE"])  or "Minute"

    if not seconds or seconds <= 0 then return "0 " .. minuteS end

    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    local parts = {}
    if days > 0 then
        parts[#parts + 1] = days .. " " .. ((days == 1) and dayL or dayS)
    end
    if hours > 0 then
        parts[#parts + 1] = hours .. " " .. ((hours == 1) and hourL or hourS)
    end
    if minutes > 0 or #parts == 0 then
        parts[#parts + 1] = minutes .. " " .. ((minutes == 1) and minuteL or minuteS)
    end

    return table.concat(parts, " ")
end

--============================================================================
-- ICON HELPERS
--============================================================================

---Check if a texture string is an atlas name (no path separators)
---@param texturePath string|number|nil The texture value to check
---@return boolean Whether the value is an atlas name
function Utilities:IsAtlasName(texturePath)
    if not texturePath or type(texturePath) == "number" then return false end
    if type(texturePath) ~= "string" then return false end
    return not texturePath:find("\\") and not texturePath:find("/")
end

--============================================================================
-- CURRENCY DISPLAY (season progress — Dawncrests, Coffer Key Shards)
--============================================================================

local CC_CAP_OPEN = "|cff80ff80"
local CC_CAPPED   = "|cffff5959"
local CC_WHITE    = "|cffffffff"
local CC_MUTED    = "|cff888888"
local EM_DASH_CUR = "\226\128\148"

--- Season-split (Dawncrests, Coffer Key Shards): row is always Current (on-hand quantity) / Season Max.
--- Cap color follows season progress: totalEarned >= seasonMax when totalEarned is known.
--- Weekly-only cap (no seasonMax): Current / weekly cap with qty vs maxQuantity.
---@param cd table|nil WarbandNexus:GetCurrencyData result
---@return string
function Utilities.FormatCurrencySeasonProgressLine(cd)
    local fmtNum = ns.UI_FormatNumber or function(n) return tostring(n or 0) end
    if not cd then
        return CC_MUTED .. "0|r"
    end
    local qty = tonumber(cd.quantity) or 0
    local maxQ = tonumber(cd.maxQuantity) or 0
    local te = cd.totalEarned
    local sm = tonumber(cd.seasonMax) or 0
    if sm > 0 then
        local teNum = tonumber(te)
        local numColor
        if teNum ~= nil then
            numColor = (teNum >= sm) and CC_CAPPED or CC_CAP_OPEN
        else
            numColor = CC_WHITE
        end
        return numColor .. fmtNum(qty) .. "|r " .. CC_MUTED .. "/ " .. fmtNum(sm) .. "|r"
    end
    if maxQ > 0 then
        local isCapped = qty >= maxQ
        local numColor = isCapped and CC_CAPPED or CC_CAP_OPEN
        return numColor .. fmtNum(qty) .. "|r " .. CC_MUTED .. "/ " .. fmtNum(maxQ) .. "|r"
    end
    if qty > 0 then
        return CC_WHITE .. fmtNum(qty) .. "|r"
    end
    return CC_MUTED .. EM_DASH_CUR .. "|r"
end

--============================================================================
-- WOWHEAD URL
--============================================================================

local WOWHEAD_TYPE_MAP = {
    mount       = "spell",
    pet         = "npc",
    toy         = "item",
    achievement = "achievement",
    item        = "item",
    quest       = "quest",
    spell       = "spell",
    npc         = "npc",
    currency    = "currency",
    illusion    = "item",
    title       = "title",
}

---Build a Wowhead URL for a given collectible/entity type and ID.
---@param entityType string "mount"|"pet"|"toy"|"achievement"|"item"|"quest"|"spell"|"npc"|"currency"|"illusion"|"title"
---@param id number
---@return string|nil url
function Utilities:GetWowheadURL(entityType, id)
    if not entityType or not id or id <= 0 then return nil end
    local wowheadType = WOWHEAD_TYPE_MAP[entityType]
    if not wowheadType then return nil end
    return "https://www.wowhead.com/" .. wowheadType .. "=" .. id
end

--============================================================================
-- EXPORT
--============================================================================

return Utilities
