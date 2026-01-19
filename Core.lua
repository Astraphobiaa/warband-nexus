--[[
    Warband Nexus - Core Module
    Main addon initialization and control logic
    
    A modern and functional Warband management system for World of Warcraft
]]

local ADDON_NAME, ns = ...

---@class WarbandNexus : AceAddon, AceEvent-3.0, AceConsole-3.0, AceHook-3.0, AceTimer-3.0, AceBucket-3.0
local WarbandNexus = LibStub("AceAddon-3.0"):NewAddon(
    ADDON_NAME,
    "AceEvent-3.0",
    "AceConsole-3.0",
    "AceHook-3.0",
    "AceTimer-3.0",
    "AceBucket-3.0"
)

-- Store in namespace for module access
ns.WarbandNexus = WarbandNexus

-- Localization
-- Note: Language override is applied in OnInitialize (after DB loads)
-- At this point, we use default game locale
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
ns.L = L

-- Constants
local WARBAND_TAB_COUNT = 5

-- Feature Flags
local ENABLE_GUILD_BANK = false -- Set to true when ready to enable Guild Bank features

-- Warband Bank Bag IDs (13-17, NOT 12!)
local WARBAND_BAGS = {
    Enum.BagIndex.AccountBankTab_1 or 13,
    Enum.BagIndex.AccountBankTab_2 or 14,
    Enum.BagIndex.AccountBankTab_3 or 15,
    Enum.BagIndex.AccountBankTab_4 or 16,
    Enum.BagIndex.AccountBankTab_5 or 17,
}

-- Personal Bank Bag IDs
-- Note: NUM_BANKBAGSLOTS is typically 7, plus the main bank slot
local PERSONAL_BANK_BAGS = {}

-- Main bank container (BANK = -1 in most clients)
if Enum.BagIndex.Bank then
    table.insert(PERSONAL_BANK_BAGS, Enum.BagIndex.Bank)
end

-- Bank bag slots (6-11 in TWW, bag 12 is Warband now!)
for i = 1, NUM_BANKBAGSLOTS or 7 do
    local bagEnum = Enum.BagIndex["BankBag_" .. i]
    if bagEnum then
        -- Skip bag 12 - it's now Warband's first tab in TWW!
        if bagEnum ~= 12 and bagEnum ~= Enum.BagIndex.AccountBankTab_1 then
        table.insert(PERSONAL_BANK_BAGS, bagEnum)
        end
    end
end

-- Fallback: if enums didn't work, use numeric IDs (6-11, NOT 12!)
if #PERSONAL_BANK_BAGS == 0 then
    PERSONAL_BANK_BAGS = { -1, 6, 7, 8, 9, 10, 11 }
end

-- Item Categories for grouping
local ITEM_CATEGORIES = {
    WEAPON = 1,
    ARMOR = 2,
    CONSUMABLE = 3,
    TRADEGOODS = 4,  -- Materials
    RECIPE = 5,
    GEM = 6,
    MISCELLANEOUS = 7,
    QUEST = 8,
    CONTAINER = 9,
    OTHER = 10,
}

-- Export to namespace
ns.WARBAND_BAGS = WARBAND_BAGS
ns.PERSONAL_BANK_BAGS = PERSONAL_BANK_BAGS
ns.WARBAND_TAB_COUNT = WARBAND_TAB_COUNT
ns.ITEM_CATEGORIES = ITEM_CATEGORIES

-- Performance: Local function references
local format = string.format
local floor = math.floor
local date = date
local time = time

--[[
    Database Defaults
    Profile-based structure for per-character settings
    Global structure for cross-character data (Warband cache)
]]
local defaults = {
    profile = {
        enabled = true,
        minimap = {
            hide = false,
            minimapPos = 220,
            lock = false,
        },
        
        -- Bank addon conflict resolution (per-addon choices)
        bankConflictChoices = {},
        
        -- Track which addons were toggled by user's choice
        toggledAddons = {},  -- { ["ElvUI"] = "disabled", ["Bagnon"] = "enabled" }
        
        -- Behavior settings
        autoScan = true,           -- Auto-scan when bank opens
        autoOpenWindow = true,     -- Auto-open addon window when bank opens
        autoSaveChanges = true,    -- Live sync while bank is open
        replaceDefaultBank = true, -- Replace default bank UI with addon
        bankModuleEnabled = true,  -- Enable bank UI replacement features (conflict checks, UI suppression, etc.)
        debugMode = false,         -- Debug logging (verbose)
        
        -- Module toggles (disable to stop API calls for that feature)
        modulesEnabled = {
            items = true,        -- Bank items scanning and display
            storage = true,      -- Cross-character storage browser
            pve = true,          -- Great Vault, M+, Lockouts tracking
            currencies = true,   -- Currency tracking
            reputations = true,  -- Reputation tracking
        },
        
        -- Weekly Planner settings
        showWeeklyPlanner = true,      -- Show Weekly Planner section in Characters tab
        weeklyPlannerDays = 3,         -- Only show chars logged in within X days
        weeklyPlannerCollapsed = false, -- Collapse state of the planner section
        
        -- Currency settings
        currencyFilterMode = "filtered",  -- "filtered" or "nonfiltered"
        currencyShowZero = true,  -- Show currencies with 0 quantity
        
        -- Reputation settings
        reputationExpanded = {},  -- Collapse/expand state for reputation headers
        
        -- Display settings
        showItemLevel = true,
        
        -- Theme Colors (RGB 0-1 format) - All calculated from master color
        themeColors = {
            accent = {0.40, 0.20, 0.58},      -- Master theme color (purple)
            accentDark = {0.28, 0.14, 0.41},  -- Darker variation (0.7x)
            border = {0.20, 0.20, 0.25},      -- Desaturated border
            tabActive = {0.20, 0.12, 0.30},   -- Active tab background (0.5x)
            tabHover = {0.24, 0.14, 0.35},    -- Hover tab background (0.6x)
        },
        showItemCount = true,
        
        -- Gold settings
        goldReserve = 0,           -- Minimum gold to keep when depositing
        
        -- Tab filtering (true = ignored)
        ignoredTabs = {
            [1] = false,
            [2] = false,
            [3] = false,
            [4] = false,
            [5] = false,
        },
        
        -- Storage tab expanded state
        storageExpanded = {
            warband = true,  -- Warband Bank expanded by default
            personal = false,  -- Personal collapsed by default
            categories = {},  -- {["warband_TradeGoods"] = true, ["personal_CharName_TradeGoods"] = false}
        },
        
        -- Character list sorting preferences
        characterSort = {
            key = nil,        -- nil = no sorting (default order), "name", "level", "gold", "lastSeen"
            ascending = true, -- true = ascending, false = descending
        },
        
        -- PvE list sorting preferences
        pveSort = {
            key = nil,        -- nil = no sorting (default order)
            ascending = true,
        },
        
        -- Notification settings
        notifications = {
            enabled = true,                    -- Master toggle
            showUpdateNotes = true,            -- Show changelog on new version
            showVaultReminder = true,          -- Show vault reminder
            showLootNotifications = true,      -- Show mount/pet/toy loot notifications
            lastSeenVersion = "0.0.0",         -- Last addon version seen
            lastVaultCheck = 0,                -- Last time vault was checked
            dismissedNotifications = {},       -- Array of dismissed notification IDs
        },
    },
    global = {
        -- Database version for migration tracking
        dataVersion = 1,  -- Will be set to 2 after migration
        
        -- Warband bank cache (SHARED across all characters) - working storage
        warbandBank = {
            items = {},            -- { [bagID] = { [slotID] = itemData } }
            gold = 0,              -- Warband bank gold
            lastScan = 0,          -- Last scan timestamp
        },
        
        -- ========== WARBAND BANK V2 STORAGE (COMPRESSED) ==========
        warbandBankV2 = nil,       -- { compressed, items, metadata }
        warbandBankLastUpdate = 0,
        
        -- ========== CURRENCY-CENTRIC STORAGE (v2) ==========
        -- Metadata stored once per currency, quantities per character
        -- Structure: { [currencyID] = { name, icon, maxQuantity, category, isAccountWide, value/chars } }
        currencies = {},
        currencyHeaders = {},  -- Header structure for UI display
        currencyLastUpdate = 0,
        
        -- ========== REPUTATION-CENTRIC STORAGE (v2) ==========
        -- Metadata stored once per faction, progress per character
        -- Structure: { [factionID] = { name, icon, isMajorFaction, isAccountWide, header, value/chars } }
        reputations = {},
        reputationHeaders = {},  -- Header structure for UI display
        factionMetadata = {},    -- Detailed faction metadata
        reputationLastUpdate = 0,
        
        -- ========== PVE-CENTRIC STORAGE (v2) ==========
        -- Global metadata for dungeons, raids, activities
        pveMetadata = {
            dungeons = {},     -- { [mapID] = { name, texture } }
            raids = {},        -- { [instanceID] = { name, texture } }
            lastUpdate = 0,
        },
        -- Per-character PvE progress
        -- Structure: { [charKey] = { greatVault, lockouts, mythicPlus } }
        pveProgress = {},
        
        -- ========== ITEMS STORAGE (v2) ==========
        -- Compressed item data for reduced file size
        -- Personal bank items per character (compressed)
        personalBanks = {},  -- { [charKey] = compressed_data }
        personalBanksLastUpdate = 0,
        
        -- All tracked characters (minimal data in v2)
        -- Key: "CharacterName-RealmName"
        -- v2: No longer stores currencies/reputations/pve/personalBank per character
        characters = {},
        
        -- Favorite characters (always shown at top)
        -- Array of "CharacterName-RealmName" keys
        favoriteCharacters = {},
        
        -- ========== PLANS STORAGE ==========
        -- User-selected goals for mounts, pets, toys, recipes
        plans = {},  -- Array of plan objects
        -- Plan structure: { id, type, itemID, mountID/petID/recipeID, name, icon, source, addedAt, notes }
        plansNextID = 1,  -- Auto-increment ID for plans
        
        -- Window size persistence
        window = {
            width = 700,
            height = 550,
        },
    },
    char = {
        -- Personal bank cache (per-character)
        personalBank = {
            items = {},
            lastScan = 0,
        },
        lastKnownGold = 0,
    },
}

-- ============================================================================
-- LIBDEFLATE COMPRESSION HELPERS (v2)
-- ============================================================================

-- Lazy-load LibDeflate to avoid errors if not available
local LibDeflate = nil
local AceSerializer = nil

local function GetLibDeflate()
    if LibDeflate == nil then
        LibDeflate = LibStub and LibStub("LibDeflate", true)
    end
    return LibDeflate
end

local function GetAceSerializer()
    if AceSerializer == nil then
        AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
    end
    return AceSerializer
end

--[[
    Compress a table using LibDeflate
    @param tbl table - Table to compress
    @return string|nil - Compressed data or nil if failed
]]
function WarbandNexus:CompressTable(tbl)
    if not tbl then return nil end
    
    local Serializer = GetAceSerializer()
    local Deflate = GetLibDeflate()
    
    if not Serializer or not Deflate then
        -- Fallback: return table as-is if libraries not available
        return tbl
    end
    
    local success, serialized = pcall(function()
        return Serializer:Serialize(tbl)
    end)
    
    if not success or not serialized then
        return nil
    end
    
    local compressed = Deflate:CompressDeflate(serialized, {level = 9})
    if not compressed then
        return nil
    end
    
    -- Encode for safe storage in SavedVariables
    return Deflate:EncodeForPrint(compressed)
end

--[[
    Decompress data back to a table
    @param compressedData string - Compressed data string
    @return table|nil - Decompressed table or nil if failed
]]
function WarbandNexus:DecompressTable(compressedData)
    if not compressedData then return nil end
    
    -- If it's already a table, return as-is (uncompressed data)
    if type(compressedData) == "table" then
        return compressedData
    end
    
    local Serializer = GetAceSerializer()
    local Deflate = GetLibDeflate()
    
    if not Serializer or not Deflate then
        return nil
    end
    
    -- Decode from print-safe format
    local decoded = Deflate:DecodeForPrint(compressedData)
    if not decoded then
        return nil
    end
    
    local decompressed = Deflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil
    end
    
    local success, deserialized = Serializer:Deserialize(decompressed)
    if not success then
        return nil
    end
    
    return deserialized
end

--[[
    Initialize the addon
    Called when the addon is first loaded
]]
function WarbandNexus:OnInitialize()
    -- Initialize database with defaults
    self.db = LibStub("AceDB-3.0"):New("WarbandNexusDB", defaults, true)
    
    -- Register database callbacks for profile changes
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    
    -- Ensure theme colors are fully calculated (for migration from old versions)
    if self.db.profile.themeColors then
        local colors = self.db.profile.themeColors
        -- If missing calculated variations, regenerate them
        if not colors.accentDark or not colors.tabHover then
            if ns.UI_CalculateThemeColors and colors.accent then
                local accent = colors.accent
                self.db.profile.themeColors = ns.UI_CalculateThemeColors(accent[1], accent[2], accent[3])
            end
        end
    end
    
    -- Initialize SessionCache from SavedVariables (LibDeflate + AceSerialize)
    if self.DecompressAndLoad then
        self:DecompressAndLoad()
    end
    
    -- ONE-TIME MIGRATION: Force reputation metadata update if missing isAccountWide
    -- This ensures existing users get the new API-based categorization
    if self.db.global.reputations and not self.db.global.reputationMigrationV2 then
        local needsMigration = false
        for factionID, repData in pairs(self.db.global.reputations) do
            if repData and repData.isAccountWide == nil then
                needsMigration = true
                break
            end
        end
        
        if needsMigration then
            self:Print("|cffff9900Migrating reputation data to v2 (API-based)|r")
            -- Mark migration done to prevent repeated runs
            self.db.global.reputationMigrationV2 = true
            -- The actual update will happen on next ScanReputations() which runs on PLAYER_ENTERING_WORLD
        end
    end
    
    -- ONE-TIME MIGRATION: Add gender field to existing characters
    -- This runs on every login until all characters are fixed
    if self.db.global.characters then
        local currentName = UnitName("player")
        local currentRealm = GetRealmName()
        local currentKey = currentName .. "-" .. currentRealm
        
        -- Fix current character's gender on every login (in case it's wrong)
        if self.db.global.characters[currentKey] then
            local savedGender = self.db.global.characters[currentKey].gender
            
            -- Detect current gender using C_PlayerInfo (most reliable)
            local detectedGender = UnitSex("player")
            local raceInfo = C_PlayerInfo.GetRaceInfo and C_PlayerInfo.GetRaceInfo()
            if raceInfo and raceInfo.gender ~= nil then
                detectedGender = (raceInfo.gender == 1) and 3 or 2
            end
            
            -- Update if different or missing
            if not savedGender or savedGender ~= detectedGender then
                self.db.global.characters[currentKey].gender = detectedGender
                self:Debug(string.format("Gender auto-fix: %s → %s", 
                    savedGender and (savedGender == 3 and "Female" or "Male") or "Unknown",
                    detectedGender == 3 and "Female" or "Male"))
            end
        end
        
        -- ONE-TIME: Add default gender to characters that don't have it
        if not self.db.global.genderMigrationV1 then
            local updated = 0
            for charKey, charData in pairs(self.db.global.characters) do
                if charData and not charData.gender then
                    -- Default to male (2) - will be corrected on next login
                    charData.gender = 2
                    updated = updated + 1
                end
            end
            if updated > 0 then
                self:Debug("Gender migration: Added default gender to " .. updated .. " characters")
            end
            self.db.global.genderMigrationV1 = true
        end
        
        -- AGGRESSIVE CLEANUP: Convert totalCopper to gold/silver/copper breakdown
        -- This runs on EVERY load to ensure SavedVariables doesn't exceed 32-bit limits
        for charKey, charData in pairs(self.db.global.characters) do
            if charData then
                -- If old totalCopper exists, convert to breakdown
                if charData.totalCopper then
                    local totalCopper = math.floor(tonumber(charData.totalCopper) or 0)
                    charData.gold = math.floor(totalCopper / 10000)
                    charData.silver = math.floor((totalCopper % 10000) / 100)
                    charData.copper = math.floor(totalCopper % 100)
                    -- DELETE old field to prevent overflow
                    charData.totalCopper = nil
                end
                
                -- If very old format exists (gold/silver/copper as separate fields), ensure floored
                if charData.gold or charData.silver or charData.copper then
                    charData.gold = math.floor(tonumber(charData.gold) or 0)
                    charData.silver = math.floor(tonumber(charData.silver) or 0)
                    charData.copper = math.floor(tonumber(charData.copper) or 0)
                end
                
                -- CRITICAL: Delete ALL legacy fields that might cause overflow
                charData.goldAmount = nil
                charData.silverAmount = nil
                charData.copperAmount = nil
            end
        end
        
        -- Clean warband bank - convert to breakdown format
        if self.db.global.warbandBank then
            local wb = self.db.global.warbandBank
            
            -- If old totalCopper exists, convert to breakdown
            if wb.totalCopper then
                local totalCopper = math.floor(tonumber(wb.totalCopper) or 0)
                wb.gold = math.floor(totalCopper / 10000)
                wb.silver = math.floor((totalCopper % 10000) / 100)
                wb.copper = math.floor(totalCopper % 100)
                wb.totalCopper = nil  -- DELETE to prevent overflow
            end
            
            -- Ensure breakdown values are integers
            if wb.gold or wb.silver or wb.copper then
                wb.gold = math.floor(tonumber(wb.gold) or 0)
                wb.silver = math.floor(tonumber(wb.silver) or 0)
                wb.copper = math.floor(tonumber(wb.copper) or 0)
            end
            
            -- Delete legacy fields
            wb.goldAmount = nil
            wb.silverAmount = nil
            wb.copperAmount = nil
        end
    end
    
    -- CollectionScanner will be initialized in OnEnable with delay
    
    -- CRITICAL FIX: Register PLAYER_ENTERING_WORLD early via raw frame
    -- This ensures we catch the event even if it fires before AceEvent is ready
    -- Direct timer-based save bypasses handler chain issues
    if not self._rawEventFrame then
        self._rawEventFrame = CreateFrame("Frame")
        self._rawEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self._rawEventFrame:SetScript("OnEvent", function(frame, event, isInitialLogin, isReloadingUi)
            -- Direct save after 2 second delay for character data to load
            C_Timer.After(2, function()
                if WarbandNexus and WarbandNexus.SaveCharacter then
                    WarbandNexus:SaveCharacter()
                end
            end)
        end)
    end
    
    -- Initialize configuration (defined in Config.lua)
    self:InitializeConfig()
    
    -- Setup slash commands
    self:RegisterChatCommand("wn", "SlashCommand")
    self:RegisterChatCommand("warbandnexus", "SlashCommand")
    
    -- Register PLAYER_LOGOUT event for SessionCache compression
    self:RegisterEvent("PLAYER_LOGOUT", "OnPlayerLogout")
    
    -- Initialize minimap button (LibDBIcon)
    C_Timer.After(1, function()
        if WarbandNexus and WarbandNexus.InitializeMinimapButton then
            WarbandNexus:InitializeMinimapButton()
        end
    end)
    
end

--[[
    Enable the addon
    Called when the addon becomes enabled
]]
function WarbandNexus:OnEnable()
    -- Reset session-only flags
    self.classicModeThisSession = false
    
    -- Refresh colors from database on enable
    if ns.UI_RefreshColors then
        ns.UI_RefreshColors()
    end
    
    -- Initialize CollectionScanner with delay (background scan after login)
    -- Delay prevents freeze during initial addon load
    C_Timer.After(2, function()
        if WarbandNexus.CollectionScanner and WarbandNexus.CollectionScanner.Initialize then
            WarbandNexus.CollectionScanner:Initialize()
            WarbandNexus:Debug("CollectionScanner initialized (background)")
        end
    end)
    
    -- UNIFIED: Register collection invalidation events
    local COLLECTION_EVENTS = {
        ["NEW_MOUNT_ADDED"] = "mount",
        ["NEW_PET_ADDED"] = "pet",
        ["NEW_TOY_ADDED"] = "toy",
        ["ACHIEVEMENT_EARNED"] = "achievement",
        ["TRANSMOG_COLLECTION_UPDATED"] = "illusion",
        -- Titles don't have a specific event, they're checked on demand
    }
    
    for event, collectionType in pairs(COLLECTION_EVENTS) do
        self:RegisterEvent(event, function()
            if self.CollectionScanner and self.CollectionScanner.InvalidateCache then
                self.CollectionScanner:InvalidateCache(collectionType)
                self:Debug("Collection cache invalidated: " .. collectionType)
            end
        end)
    end
    
    -- CRITICAL: Check for addon conflicts immediately on enable (only if bank module enabled)
    -- This runs on both initial login AND /reload
    -- Detect if user re-enabled conflicting addons/modules
    C_Timer.After(0.5, function()
        if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then
            return
        end
        
        -- Skip conflict detection if bank module is disabled
        if not WarbandNexus.db.profile.bankModuleEnabled then
            return
        end
        
        -- Check if there are existing conflict choices
        local hasConflictChoices = next(WarbandNexus.db.profile.bankConflictChoices) ~= nil
        
        -- Detect all currently conflicting addons
        local conflicts = WarbandNexus:DetectBankAddonConflicts()
        
        -- Reset choices for re-enabled addons (if conflict exists AND choice was useWarband)
        if conflicts and #conflicts > 0 and WarbandNexus.db.profile.bankConflictChoices then
            for _, addonName in ipairs(conflicts) do
                local choice = WarbandNexus.db.profile.bankConflictChoices[addonName]
                
                if choice == "useWarband" then
                    -- User chose Warband but addon is back, reset choice
                    WarbandNexus.db.profile.bankConflictChoices[addonName] = nil
                    WarbandNexus:Print("|cffffaa00" .. addonName .. " was re-enabled! Choose again...|r")
                end
            end
        end
        
        -- Call CheckBankConflictsOnLogin if:
        -- 1. No choices exist yet (fresh enable or choices were reset)
        -- 2. OR conflicts detected that need resolution
        if not hasConflictChoices or (conflicts and #conflicts > 0) then
            C_Timer.After(1, function()
                if WarbandNexus and WarbandNexus.CheckBankConflictsOnLogin then
                    WarbandNexus:CheckBankConflictsOnLogin()
                end
            end)
        end
    end)
    
    -- Initialize conflict queue and guards
    self._conflictQueue = {}
    self._isProcessingConflict = false
    
    -- Session flag to prevent duplicate saves
    self.characterSaved = false
    
    -- Register events
    self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded") -- Detect when conflicting addons are loaded
    self:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
    self:RegisterEvent("BANKFRAME_CLOSED", "OnBankClosed")
    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", "OnBagUpdate") -- Personal bank slot changes
    
    -- Guild Bank events (disabled by default, set ENABLE_GUILD_BANK=true to enable)
    if ENABLE_GUILD_BANK then
        self:RegisterEvent("GUILDBANKFRAME_OPENED", "OnGuildBankOpened")
        self:RegisterEvent("GUILDBANKFRAME_CLOSED", "OnGuildBankClosed")
        self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", "OnBagUpdate") -- Guild bank slot changes
    end
    
    self:RegisterEvent("PLAYER_MONEY", "OnMoneyChanged")
    self:RegisterEvent("ACCOUNT_MONEY", "OnMoneyChanged") -- Warband Bank gold changes
    
    -- Currency & Reputation events - will be replaced with throttled versions by EventManager
    -- Initial registration for fallback (EventManager overrides with incremental updates)
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "OnCurrencyChanged")
    self:RegisterEvent("UPDATE_FACTION", "OnReputationChanged")
    self:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "OnReputationChanged")
    self:RegisterEvent("MAJOR_FACTION_UNLOCKED", "OnReputationChanged")
    -- Note: QUEST_LOG_UPDATE removed - too noisy, not needed for reputation tracking
    
    -- M+ completion events (for cache updates)
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED")  -- Fires when M+ run completes
    self:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD")  -- Fires when new best time
    
    -- Combat protection for UI (taint prevention)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart") -- Entering combat
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")  -- Leaving combat
    
    -- PvE tracking events are now managed by EventManager (throttled versions)
    -- See Modules/EventManager.lua InitializeEventManager()
    
    -- Collection tracking events are now managed by EventManager (debounced versions)
    -- See Modules/EventManager.lua InitializeEventManager()
    
    -- Register bucket events for bag updates (fast refresh for responsive UI)
    self:RegisterBucketEvent("BAG_UPDATE", 0.15, "OnBagUpdate")
    
    -- Setup BankFrame suppress hook
    -- This prevents BankFrame from showing when bank is opened
    C_Timer.After(1, function()
        if WarbandNexus and WarbandNexus.SetupBankFrameHook then
            WarbandNexus:SetupBankFrameHook()
        end
    end)
    
    -- Hook container clicks to ensure UI refreshes on item move
    -- Note: ContainerFrameItemButton_OnModifiedClick was removed in TWW (11.0+)
    -- We now rely on BAG_UPDATE_DELAYED event for UI updates
    if not self.containerHooked then
        self.containerHooked = true
    end
    
    -- Initialize advanced modules
    -- API Wrapper: Initialize first (other modules may use it)
    if self.InitializeAPIWrapper then
        self:InitializeAPIWrapper()
    end
    
    -- Cache Manager: Smart caching for performance
    if self.WarmupCaches then
        C_Timer.After(2, function()
            if WarbandNexus and WarbandNexus.WarmupCaches then
                WarbandNexus:WarmupCaches()
            end
        end)
    end
    
    -- Event Manager: Throttled/debounced event handling
    if self.InitializeEventManager then
        C_Timer.After(0.5, function()
            if WarbandNexus and WarbandNexus.InitializeEventManager then
                WarbandNexus:InitializeEventManager()
            end
        end)
    end
    
    -- Tooltip Enhancer: Add item locations to tooltips
    if self.InitializeTooltipEnhancer then
        C_Timer.After(0.5, function()
            if WarbandNexus and WarbandNexus.InitializeTooltipEnhancer then
                WarbandNexus:InitializeTooltipEnhancer()
            end
        end)
    end
    
    -- Tooltip Click Handler: Shift+Click to search
    if self.InitializeTooltipClickHandler then
        C_Timer.After(0.5, function()
            if WarbandNexus and WarbandNexus.InitializeTooltipClickHandler then
                WarbandNexus:InitializeTooltipClickHandler()
            end
        end)
    end
    
    -- Error Handler: Wrap critical functions for production safety
    -- NOTE: This must run AFTER all other modules are loaded
    if self.InitializeErrorHandler then
        C_Timer.After(1.5, function()
            if WarbandNexus and WarbandNexus.InitializeErrorHandler then
                WarbandNexus:InitializeErrorHandler()
            end
        end)
    end
    
    -- Database Optimizer: Auto-cleanup and optimization
    if self.InitializeDatabaseOptimizer then
        C_Timer.After(5, function()
            if WarbandNexus and WarbandNexus.InitializeDatabaseOptimizer then
                WarbandNexus:InitializeDatabaseOptimizer()
            end
        end)
    end

    -- Collection Tracking: Mount/Pet/Toy detection
    -- CollectionManager handles bag scanning and event registration
    C_Timer.After(1, function()
        if WarbandNexus and WarbandNexus.InitializeCollectionTracking then
            WarbandNexus:InitializeCollectionTracking()
        else
            WarbandNexus:Print("|cffff0000ERROR: InitializeCollectionTracking not found!|r")
        end
    end)

    -- Print loaded message
    self:Print(L["ADDON_LOADED"])
end

--[[
    Save character data - called once per login
]]
function WarbandNexus:SaveCharacter()
    -- Prevent duplicate saves
    if self.characterSaved then
        return
    end
    
    local success, err = pcall(function()
        self:SaveCurrentCharacterData()
    end)
    
    if success then
        self.characterSaved = true
    else
        self:Print("Error saving character: " .. tostring(err))
    end
end

--[[
    Get character's total copper (calculated from gold/silver/copper breakdown)
    @param charData table - Character data from SavedVariables
    @return number - Total copper amount
]]
function WarbandNexus:GetCharTotalCopper(charData)
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



--[[
    Disable the addon
    Called when the addon becomes disabled
]]
function WarbandNexus:OnDisable()
    -- Unregister all events
    self:UnregisterAllEvents()
    self:UnregisterAllBuckets()
end

--[[
    Handle PLAYER_LOGOUT event
    Compress and save SessionCache to SavedVariables
]]
function WarbandNexus:OnPlayerLogout()
    -- Compress and save session cache (LibDeflate + AceSerialize)
    if self.CompressAndSave then
        self:CompressAndSave()
    end
end

--[[
    Handle profile changes
    Refresh settings when profile is changed/copied/reset
]]
function WarbandNexus:OnProfileChanged()
    -- Refresh UI elements if they exist
    if self.RefreshUI then
        self:RefreshUI()
    end
    
end

--[[
    Slash command handler
    @param input string The command input
]]
function WarbandNexus:SlashCommand(input)
    local cmd = self:GetArgs(input, 1)
    
    -- No command - open addon window
    if not cmd or cmd == "" then
        self:ShowMainWindow()
        return
    end
    
    -- Help command - show available commands
    if cmd == "help" then
        self:Print("|cff00ccffWarband Nexus|r - Available commands:")
        self:Print("  |cff00ccff/wn|r - Open addon window")
        self:Print("  |cff00ccff/wn options|r - Open settings")
        self:Print("  |cff00ccff/wn debug|r - Toggle debug mode")
        self:Print("  |cff00ccff/wn scanquests [tww|df|sl]|r - Scan & debug daily quests")
        self:Print("  |cff00ccff/wn cleanup|r - Remove inactive characters (90+ days)")
        self:Print("  |cff00ccff/wn resetrep|r - Reset reputation data (rebuild from API)")
        self:Print("  |cff888888/wn testloot [type]|r - Test notifications (mount/pet/toy/etc)")
        self:Print("  |cff888888/wn testeffect|r - Test visual effects (glow/flash/border)")
        self:Print("  |cff888888/wn testvault|r - Test weekly vault slot notification")
        return
    end
    
    -- Public commands (always available)
    if cmd == "show" or cmd == "toggle" or cmd == "open" then
        self:ShowMainWindow()
        return
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        self:OpenOptions()
        return
    elseif cmd == "cleanup" then
        if self.CleanupStaleCharacters then
            local removed = self:CleanupStaleCharacters(90)
            if removed == 0 then
                self:Print("|cff00ff00No inactive characters found (90+ days)|r")
            else
                self:Print("|cff00ff00Removed " .. removed .. " inactive character(s)|r")
            end
        end
        return
    elseif cmd == "resetrep" then
        -- Reset reputation data (clear old structure, rebuild from API)
        self:Print("|cffff9900Resetting reputation data...|r")
        self:Print("|cffff9900Debug logs will show API responses|r")
        
        -- Clear old metadata (v2: global storage)
        if self.db.global.factionMetadata then
            self.db.global.factionMetadata = {}
        end
        
        -- Clear global reputation data (v2)
        if self.db.global.reputations then
            self.db.global.reputations = {}
        end
        if self.db.global.reputationHeaders then
            self.db.global.reputationHeaders = {}
        end
        
        local playerKey = UnitName("player") .. "-" .. GetRealmName()
        
        -- Invalidate cache
        if self.InvalidateReputationCache then
            self:InvalidateReputationCache(playerKey)
        end
        
        -- Rebuild metadata and scan
        if self.BuildFactionMetadata then
            self:BuildFactionMetadata()
        end
        
        if self.ScanReputations then
            C_Timer.After(0.5, function()
                self.currentTrigger = "CMD_RESET"
                self:ScanReputations()
                self:Print("|cff00ff00Reputation data reset complete! Reloading UI...|r")
                
                -- Refresh UI
                if self.RefreshUI then
                    self:RefreshUI()
                end
            end)
        end
        
        return
    elseif cmd == "debug" then
        -- Hidden debug mode toggle (for developers)
        self.db.profile.debugMode = not self.db.profile.debugMode
        if self.db.profile.debugMode then
            self:Print("|cff00ff00Debug mode enabled|r")
        else
            self:Print("|cffff9900Debug mode disabled|r")
        end
        return
    elseif cmd == "spacing" then
        -- Debug UI spacing constants
        self:Print("=== UI Spacing Constants ===")
        if ns.UI_LAYOUT then
            self:Print("HEADER_SPACING (Should be 40): " .. tostring(ns.UI_LAYOUT.HEADER_SPACING))
            self:Print("ROW_SPACING (Should be 28): " .. tostring(ns.UI_LAYOUT.ROW_SPACING))
            self:Print("ROW_HEIGHT: " .. tostring(ns.UI_LAYOUT.ROW_HEIGHT))
            self:Print("betweenRows: " .. tostring(ns.UI_LAYOUT.betweenRows))
            self:Print("headerSpacing (Old): " .. tostring(ns.UI_LAYOUT.headerSpacing))
            self:Print("SECTION_SPACING: " .. tostring(ns.UI_LAYOUT.SECTION_SPACING))
        else
            self:Print("Error: ns.UI_LAYOUT is nil")
        end
        return
    elseif cmd == "fixgender" then
        -- Manual gender fix command
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if self.db.global.characters and self.db.global.characters[key] then
            local currentGender = self.db.global.characters[key].gender
            local detectedGender = UnitSex("player")
            
            -- Try C_PlayerInfo as backup
            local raceInfo = C_PlayerInfo.GetRaceInfo and C_PlayerInfo.GetRaceInfo()
            if raceInfo and raceInfo.gender ~= nil then
                -- Convert: C_PlayerInfo returns 0=male, 1=female
                detectedGender = (raceInfo.gender == 1) and 3 or 2
                self:Print(string.format("|cff00ccffUsing C_PlayerInfo.GetRaceInfo().gender=%d → %d|r", 
                    raceInfo.gender, detectedGender))
            end
            
            self:Print(string.format("|cffff9900Current saved gender: %d (%s)|r", 
                currentGender or 0,
                currentGender == 3 and "Female" or (currentGender == 2 and "Male" or "Unknown")))
            self:Print(string.format("|cff00ccffDetected gender: %d (%s)|r", 
                detectedGender or 0,
                detectedGender == 3 and "Female" or (detectedGender == 2 and "Male" or "Unknown")))
            
            if detectedGender and detectedGender ~= currentGender then
                self.db.global.characters[key].gender = detectedGender
                self:Print("|cff00ff00Gender updated! Refresh UI with /wn to see changes.|r")
            else
                self:Print("|cffff0000No change needed or unable to detect gender.|r")
            end
        else
            self:Print("|cffff0000Character data not found!|r")
        end
        return
    elseif cmd == "savechar" then
        -- Manual character save command
        self:Print("|cff00ccffManually saving character data...|r")
        local success = self:SaveCurrentCharacterData()
        if success ~= false then
            self:Print("|cff00ff00Character saved successfully!|r")
        else
            self:Print("|cffff0000Failed to save character data.|r")
        end
        return
    elseif cmd == "testvault" then
        -- Test weekly vault notification
        local currentName = UnitName("player")
        if self.ShowWeeklySlotNotification then
            self:Print("|cff00ff00Testing weekly vault notification...|r")
            self:ShowWeeklySlotNotification(currentName, "world", 1, 2)
        else
            self:Print("|cffff0000Error: ShowWeeklySlotNotification not found!|r")
        end
        return
    elseif cmd == "scanquests" or cmd:match("^scanquests%s") then
        -- Scan and debug daily quests
        local contentType = cmd:match("^scanquests%s+(%S+)") or "tww"
        
        if not self.ScanDailyQuests then
            self:Print("|cffff0000Error: ScanDailyQuests not found!|r")
            return
        end
        
        self:Print("|cff00ff00Scanning daily quests for content: " .. contentType .. "|r")
        local quests = self:ScanDailyQuests(contentType)
        
        self:Print(string.format("|cff00ff00Results: %d daily, %d world, %d weekly, %d special, %d delves|r",
            #quests.dailyQuests, #quests.worldQuests, #quests.weeklyQuests,
            #quests.specialAssignments, #quests.delves))
        
        -- List daily quests
        if #quests.dailyQuests > 0 then
            self:Print("|cffaaaaaa=== Daily Quests ===|r")
            for _, quest in ipairs(quests.dailyQuests) do
                self:Print(string.format("  [%d] %s", quest.questID, quest.title))
            end
        end
        
        return
    end
    
    -- Debug commands (only work when debug mode is enabled)
    if not self.db.profile.debugMode then
        self:Print("|cffff6600Unknown command. Type |r|cff00ccff/wn help|r|cffff6600 for available commands.|r")
        return
    end
    
    -- Debug mode active - process debug commands
    if cmd == "scan" then
        self:ScanWarbandBank()
    elseif cmd == "scancurr" then
        -- Scan ALL currencies from the game
        self:Print("=== Scanning ALL Currencies ===")
        if not C_CurrencyInfo then
            self:Print("|cffff0000C_CurrencyInfo API not available!|r")
            return
        end
        
        local etherealFound = {}
        local totalScanned = 0
        
        -- Scan by iterating through possible currency IDs (brute force for testing)
        for id = 3000, 3200 do
            local info = C_CurrencyInfo.GetCurrencyInfo(id)
            if info and info.name and info.name ~= "" then
                totalScanned = totalScanned + 1
                
                -- Look for Ethereal or Season 3 related
                if info.name:match("Ethereal") or info.name:match("Season") then
                    table.insert(etherealFound, format("[%d] %s (qty: %d)", 
                        id, info.name, info.quantity or 0))
                end
            end
        end
        
        if #etherealFound > 0 then
            self:Print("|cff00ff00Found Ethereal/Season 3 currencies:|r")
            for _, line in ipairs(etherealFound) do
                self:Print(line)
            end
        else
            self:Print("|cffffcc00No Ethereal currencies found in range 3000-3200|r")
        end
        
        self:Print(format("Total currencies scanned: %d", totalScanned))
    elseif cmd == "chars" or cmd == "characters" then
        self:PrintCharacterList()
    elseif cmd == "storage" or cmd == "browse" then
        -- Show Storage tab directly
        self:ShowMainWindow()
        if self.UI and self.UI.mainFrame then
            self.UI.mainFrame.currentTab = "storage"
            if self.PopulateContent then
                self:PopulateContent()
            end
        end
    elseif cmd == "pve" then
        -- Show PvE tab directly
        self:ShowMainWindow()
        if self.UI and self.UI.mainFrame then
            self.UI.mainFrame.currentTab = "pve"
            if self.PopulateContent then
                self:PopulateContent()
            end
        end
    elseif cmd == "pvedata" or cmd == "pveinfo" then
        -- Print current character's PvE data
        self:PrintPvEData()
    elseif cmd == "enumcheck" then
        -- Debug: Check Enum values
        self:Print("=== Enum.WeeklyRewardChestThresholdType Values ===")
        if Enum and Enum.WeeklyRewardChestThresholdType then
            self:Print("  Raid: " .. tostring(Enum.WeeklyRewardChestThresholdType.Raid))
            self:Print("  Activities (M+): " .. tostring(Enum.WeeklyRewardChestThresholdType.Activities))
            self:Print("  RankedPvP: " .. tostring(Enum.WeeklyRewardChestThresholdType.RankedPvP))
            self:Print("  World: " .. tostring(Enum.WeeklyRewardChestThresholdType.World))
        else
            self:Print("  Enum.WeeklyRewardChestThresholdType not available")
        end
        self:Print("=============================================")
        -- Also collect and show current vault activities
        if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
            local activities = C_WeeklyRewards.GetActivities()
            if activities and #activities > 0 then
                self:Print("Current Vault Activities:")
                for i, activity in ipairs(activities) do
                    self:Print(string.format("  [%d] type=%s, index=%s, progress=%s/%s", 
                        i, tostring(activity.type), tostring(activity.index),
                        tostring(activity.progress), tostring(activity.threshold)))
                end
            else
                self:Print("No current vault activities")
            end
        end
    elseif cmd == "dumpbank" then
        -- Debug command to dump BankFrame structure
        if self.DumpBankFrameInfo then
            self:DumpBankFrameInfo()
        else
            self:Print("DumpBankFrameInfo not available")
        end
    elseif cmd == "cache" or cmd == "cachestats" then
        if self.PrintCacheStats then
            self:PrintCacheStats()
        else
            self:Print("CacheManager not loaded")
        end
    elseif cmd == "events" or cmd == "eventstats" then
        if self.PrintEventStats then
            self:PrintEventStats()
        else
            self:Print("EventManager not loaded")
        end
    elseif cmd == "resetprof" then
        if self.ResetProfessionData then
            self:ResetProfessionData()
            self:Print("Profession data reset.")
        else
            -- Manual fallback
            local name = UnitName("player")
            local realm = GetRealmName()
            local key = name .. "-" .. realm
            if self.db.global.characters and self.db.global.characters[key] then
                self.db.global.characters[key].professions = nil
                self:Print("Profession data manually reset")
            end
        end
    elseif cmd == "currency" or cmd == "curr" then
        -- Debug currency data
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        self:Print("=== Currency Debug ===")
        if self.db.global.characters and self.db.global.characters[key] then
            local char = self.db.global.characters[key]
            if char.currencies then
                local count = 0
                local etherealCurrencies = {}
                
                for currencyID, currency in pairs(char.currencies) do
                    count = count + 1
                    
                    -- Look for Ethereal currencies
                    if currency.name and currency.name:match("Ethereal") then
                        table.insert(etherealCurrencies, format("  [%d] %s: %d/%d (expansion: %s)", 
                            currencyID, currency.name, 
                            currency.quantity or 0, currency.maxQuantity or 0,
                            currency.expansion or "Unknown"))
                    end
                end
                
                if #etherealCurrencies > 0 then
                    self:Print("|cff00ff00Ethereal Currencies Found:|r")
                    for _, info in ipairs(etherealCurrencies) do
                        self:Print(info)
                    end
                else
                    self:Print("|cffffcc00No Ethereal currencies found!|r")
                end
                
                self:Print(format("Total currencies collected: %d", count))
            else
                self:Print("|cffff0000No currency data found!|r")
                self:Print("Running UpdateCurrencyData()...")
                if self.UpdateCurrencyData then
                    self:UpdateCurrencyData()
                    self:Print("|cff00ff00Currency data collected! Check again with /wn curr|r")
                end
            end
        else
            self:Print("|cffff0000Character not found in database!|r")
        end
    elseif cmd == "minimap" then
        if self.ToggleMinimapButton then
            self:ToggleMinimapButton()
        else
            self:Print("Minimap button module not loaded")
        end
    
    elseif cmd == "bankcheck" then
        -- Check for bank addon conflicts
        local conflicts = self:DetectBankAddonConflicts()
        
        self:Print("=== Bank Conflict Status ===")
        
        if conflicts and #conflicts > 0 then
            self:Print("Conflicting addons detected:")
            for _, addonName in ipairs(conflicts) do
                local choice = self.db.profile.bankConflictChoices[addonName]
                if choice == "useWarband" then
                    self:Print(string.format("  |cff00ccff%s|r: |cff00ff00Using Warband Nexus|r", addonName))
                elseif choice == "useOther" then
                    self:Print(string.format("  |cff00ccff%s|r: |cff888888Using %s|r", addonName, addonName))
                else
                    self:Print(string.format("  |cff00ccff%s|r: |cffff9900Not resolved yet|r", addonName))
                end
            end
            self:Print("")
            self:Print("To reset: Type |cff00ccff/wn bankreset|r")
        else
            self:Print("|cff00ff00✓ No conflicts detected|r")
            self:Print("Warband Nexus is managing your bank UI!")
        end
        
        self:Print("==========================")
    
    elseif cmd == "bankreset" then
        -- Reset ALL bank conflict choices
        self.db.profile.bankConflictChoices = {}
        self:ClearConflictCache()
        self:Print("|cff00ff00All bank conflict choices reset!|r")
        self:Print("Type |cff00ccff/reload|r to see conflict popups again.")
    
    elseif cmd == "vaultcheck" or cmd == "testvault" then
        -- Test vault notification system
        if self.TestVaultCheck then
            self:TestVaultCheck()
        else
            self:Print("Vault check module not loaded")
        end
    
    elseif cmd == "testloot" then
        -- Test loot notification system
        -- Parse the type argument (mount/pet/toy or nil for all)
        local typeArg = input:match("^testloot%s+(%w+)") -- Extract word after "testloot "
        self:Print("|cff888888[DEBUG] testloot command: typeArg = " .. tostring(typeArg) .. "|r")
        if self.TestLootNotification then
            self:TestLootNotification(typeArg)
        else
            self:Print("|cffff0000Loot notification module not loaded!|r")
            self:Print("|cffff6600Attempting to initialize...|r")
            if self.InitializeLootNotifications then
                self:InitializeLootNotifications()
                self:Print("|cff00ff00Manual initialization complete. Try /wn testloot again.|r")
            else
                self:Print("|cffff0000InitializeLootNotifications function not found!|r")
            end
        end
    
    elseif cmd == "initloot" then
        -- Debug: Force initialize loot notifications
        self:Print("|cff00ccff[DEBUG] Forcing InitializeLootNotifications...|r")
        if self.InitializeLootNotifications then
            self:InitializeLootNotifications()
        else
            self:Print("|cffff0000ERROR: InitializeLootNotifications not found!|r")
        end
    
    elseif cmd == "testeffect" then
        -- Test different visual effects on notifications
        if self.TestNotificationEffects then
            self:TestNotificationEffects()
        else
            self:Print("|cffff0000TestNotificationEffects function not found!|r")
        end

    -- Hidden/Debug commands
    elseif cmd == "errors" then
        local subCmd = self:GetArgs(input, 2, 1)
        if subCmd == "full" or subCmd == "all" then
            self:PrintRecentErrors(20)
        elseif subCmd == "clear" then
            if self.ClearErrorLog then
                self:ClearErrorLog()
            end
        elseif subCmd == "stats" then
            if self.PrintErrorStats then
                self:PrintErrorStats()
            end
        elseif subCmd == "export" then
            if self.ExportErrorLog then
                local log = self:ExportErrorLog()
                self:Print("Error log exported. Check chat for full log.")
                -- Print full log (only in debug mode for cleanliness)
                if self.db.profile.debugMode then
                    print(log)
                end
            end
        elseif tonumber(subCmd) then
            if self.ShowErrorDetails then
                self:ShowErrorDetails(tonumber(subCmd))
            end
        else
            if self.PrintRecentErrors then
                self:PrintRecentErrors(5)
            end
        end
    elseif cmd == "recover" or cmd == "emergency" then
        if self.EmergencyRecovery then
            self:EmergencyRecovery()
        end
    elseif cmd == "dbstats" or cmd == "dbinfo" then
        if self.PrintDatabaseStats then
            self:PrintDatabaseStats()
        end
    elseif cmd == "optimize" or cmd == "dboptimize" then
        if self.RunOptimization then
            self:RunOptimization()
        end
    elseif cmd == "apireport" or cmd == "apicompat" then
        if self.PrintAPIReport then
            self:PrintAPIReport()
        end
    elseif cmd == "suppress" then
        -- Manual suppress - force hide Blizzard bank UI
        self:Print("=== Manual Suppress ===")
        if self.SuppressDefaultBankFrame then
            self:SuppressDefaultBankFrame()
            self:Print("SuppressDefaultBankFrame() called")
        else
            self:Print("|cffff0000Function not found!|r")
        end
    elseif cmd == "bankstatus" or cmd == "bankinfo" then
        -- Debug: Print bank frame status
        self:Print("=== Bank Frame Status ===")
        self:Print("bankFrameSuppressed: " .. tostring(self.bankFrameSuppressed))
        self:Print("bankFrameHooked: " .. tostring(self.bankFrameHooked))
        self:Print("bankIsOpen: " .. tostring(self.bankIsOpen))
        self:Print("replaceDefaultBank setting: " .. tostring(self.db.profile.replaceDefaultBank))
        
        if BankFrame then
            self:Print("BankFrame exists: true")
            self:Print("BankFrame:IsShown(): " .. tostring(BankFrame:IsShown()))
            self:Print("BankFrame:GetAlpha(): " .. tostring(BankFrame:GetAlpha()))
            local point, relativeTo, relativePoint, xOfs, yOfs = BankFrame:GetPoint()
            self:Print("BankFrame position: " .. tostring(xOfs) .. ", " .. tostring(yOfs))
        else
            self:Print("BankFrame exists: false")
        end
        
        -- TWW: Check BankPanel
        if BankPanel then
            self:Print("BankPanel exists: true")
            self:Print("BankPanel:IsShown(): " .. tostring(BankPanel:IsShown()))
            self:Print("BankPanel:GetAlpha(): " .. tostring(BankPanel:GetAlpha()))
            local point, relativeTo, relativePoint, xOfs, yOfs = BankPanel:GetPoint()
            self:Print("BankPanel position: " .. tostring(xOfs or "nil") .. ", " .. tostring(yOfs or "nil"))
        else
            self:Print("BankPanel exists: false")
        end
        self:Print("========================")
    else
        self:Print("|cffff6600Unknown command:|r " .. cmd)
    end
end

--[[
    Print list of tracked characters
]]
function WarbandNexus:PrintCharacterList()
    self:Print("=== Tracked Characters ===")
    
    local chars = self:GetAllCharacters()
    if #chars == 0 then
        self:Print("No characters tracked yet.")
        return
    end
    
    for _, char in ipairs(chars) do
        local lastSeenText = ""
        if char.lastSeen then
            local diff = time() - char.lastSeen
            if diff < 60 then
                lastSeenText = "now"
            elseif diff < 3600 then
                lastSeenText = math.floor(diff / 60) .. "m ago"
            elseif diff < 86400 then
                lastSeenText = math.floor(diff / 3600) .. "h ago"
            else
                lastSeenText = math.floor(diff / 86400) .. "d ago"
            end
        end
        
        self:Print(string.format("  %s (%s Lv%d) - %s",
            char.name or "?",
            char.classFile or "?",
            char.level or 0,
            lastSeenText
        ))
    end
    
    self:Print("Total: " .. #chars .. " characters")
    self:Print("==========================")
end

-- InitializeDataBroker() moved to Modules/MinimapButton.lua (now InitializeMinimapButton)

--[[
    Event Handlers
]]

function WarbandNexus:OnBankOpened()
    self.bankIsOpen = true
    
    -- Check if in Classic Mode for this session
    if self.classicModeThisSession then
        -- Don't suppress Blizzard UI
        -- Don't auto-open Warband Nexus
        -- Just scan data in background
        if self.db.profile.autoScan then
            if self.ScanPersonalBank then
                self:ScanPersonalBank()
            end
        end
        return
    end
    
    -- Check if bank module UI features are enabled
    local bankModuleEnabled = self.db.profile.bankModuleEnabled
    
    -- Check if ANY conflict addon was chosen as "useOther" (background mode)
    local useOtherAddon = self:IsUsingOtherBankAddon()
    
    -- Only manage bank UI if module is enabled AND no other addon is in use
    if bankModuleEnabled and not useOtherAddon then
        -- Normal mode: WarbandNexus manages bank UI
        
        -- CRITICAL: Suppress Blizzard's bank frame immediately
        self:SuppressDefaultBankFrame()
        
        -- Read which tab Blizzard selected when bank opened
        local blizzardSelectedTab = nil
        if BankFrame then
            blizzardSelectedTab = BankFrame.selectedTab or BankFrame.activeTabIndex
            if not blizzardSelectedTab and BankFrame.TabSystem then
                blizzardSelectedTab = BankFrame.TabSystem.selectedTab
            end
        end
        
        local warbandTabID = BankFrame and BankFrame.accountBankTabID or 2
        
        -- Determine bank type: Default to Personal Bank unless Warband tab is selected
        if blizzardSelectedTab == warbandTabID then
            self.currentBankType = "warband"
        else
            self.currentBankType = "personal"
        end
        
        -- Open player bags (only in normal mode)
        if OpenAllBags then
            OpenAllBags()
        end
    end
    
    -- PERFORMANCE: Batch scan operations
    if self.db.profile.autoScan then
        if self.ScanPersonalBank then
            self:ScanPersonalBank()
        end
    end
    
    -- PERFORMANCE: Single delayed callback instead of nested timers
    C_Timer.After(0.3, function()
        if not WarbandNexus then return end
        
        -- Check Warband bank accessibility
        local firstBagID = Enum.BagIndex.AccountBankTab_1
        local numSlots = C_Container.GetContainerNumSlots(firstBagID)
        
        if numSlots and numSlots > 0 then
            WarbandNexus.warbandBankIsOpen = true
            
            -- Scan warband bank
            if WarbandNexus.db.profile.autoScan and WarbandNexus.ScanWarbandBank then
                WarbandNexus:ScanWarbandBank()
            end
        end
        
        -- CRITICAL: Check for addon conflicts when bank opens (only if module enabled)
        -- This catches runtime changes (user opened ElvUI bags settings, re-enabled module, etc.)
        if WarbandNexus.db.profile.bankModuleEnabled and WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.bankConflictChoices then
            local conflicts = WarbandNexus:DetectBankAddonConflicts()
            if conflicts and #conflicts > 0 then
                -- Check each conflict to see if user previously chose "useWarband"
                -- If so, they've re-enabled the addon/module and need to choose again
                local choicesReset = false
                
                for _, addonName in ipairs(conflicts) do
                    local choice = WarbandNexus.db.profile.bankConflictChoices[addonName]
                    
                    if choice == "useWarband" then
                        -- User previously chose Warband but addon/module is enabled again!
                        -- RESET the choice so popup will show
                        WarbandNexus.db.profile.bankConflictChoices[addonName] = nil
                        choicesReset = true
                    end
                end
                
                -- If we reset any choices OR there are new conflicts, show popup
                if choicesReset or not next(WarbandNexus.db.profile.bankConflictChoices) then
                    -- Use CheckBankConflictsOnLogin which has throttling built-in
                    if WarbandNexus.CheckBankConflictsOnLogin then
                        WarbandNexus:CheckBankConflictsOnLogin()
                    end
                end
            end
        end
        
        -- Auto-open window ONLY if bank module enabled AND using WarbandNexus mode
        local useOther = WarbandNexus:IsUsingOtherBankAddon()
        if WarbandNexus.db.profile.bankModuleEnabled and not useOther and WarbandNexus.db.profile.autoOpenWindow ~= false then
            if WarbandNexus and WarbandNexus.ShowMainWindowWithItems then
                WarbandNexus:ShowMainWindowWithItems(WarbandNexus.currentBankType)
            end
        end
    end)
end

-- Note: We no longer use UnregisterAllEvents because it triggers BANKFRAME_CLOSED
-- Instead we just hide and move the frame off-screen

--[[
    Detect conflicting bank addons (CACHED)
    @return string|nil - Name of conflicting addon, or nil if none detected
]]
function WarbandNexus:DetectBankAddonConflicts()
    -- Wrap in pcall to prevent errors from breaking the addon
    local success, conflicts = pcall(function()
        local found = {}
        
        -- TWW (11.0+) uses C_AddOns.IsAddOnLoaded(), older versions use IsAddOnLoaded()
        local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        
        -- List of known conflicting addons (popular bank/bag addons)
        local conflictingAddons = {
            -- Popular bag addons
            "Bagnon", "Combuctor", "ArkInventory", "AdiBags", "Baganator",
            "LiteBag", "TBag", "BaudBag", "Inventorian",
            -- ElvUI modules
            "ElvUI_Bags", "ElvUI",
            -- Bank-specific
            "BankStack", "BankItems", "Sorted",
            -- Generic names (legacy)
            "BankUI", "InventoryManager", "BagAddon", "BankModifier",
            "CustomBank", "AdvancedInventory", "BagSystem"
        }
        
        for _, addonName in ipairs(conflictingAddons) do
            if IsLoaded(addonName) then
                -- ElvUI special check: Only add if bags module is enabled
                if addonName == "ElvUI" then
                    -- Check if ElvUI Bags module is ACTUALLY enabled
                    local elvuiConflict = false  -- Default: no conflict
                    
                    if ElvUI then
                        local E = ElvUI[1]
                        if E then
                            -- Bags is ENABLED if ANY of these is explicitly TRUE
                            local privateBagsEnabled = false
                            local dbBagsEnabled = false
                            
                            -- Check global setting (E.private.bags.enable)
                            if E.private and E.private.bags and E.private.bags.enable == true then
                                privateBagsEnabled = true
                            end
                            
                            -- Check profile setting (E.db.bags.enabled)
                            if E.db and E.db.bags and E.db.bags.enabled == true then
                                dbBagsEnabled = true
                            end
                            
                            -- Conflict if ANY setting is enabled
                            elvuiConflict = privateBagsEnabled or dbBagsEnabled
                        else
                            -- Can't access E, assume no conflict (safer default)
                            elvuiConflict = false
                        end
                    else
                        -- ElvUI not loaded yet, no conflict
                        elvuiConflict = false
                    end
                    
                    if elvuiConflict then
                        table.insert(found, addonName)
                    end
                else
                    -- Other addons: always conflict if loaded
                    table.insert(found, addonName)
                end
            end
        end
        
        return found
    end)
    
    if success then
        return conflicts
    else
        return {}
    end
end

--[[
    Helper: Check if any conflict addon is set to "useOther"
    Safe wrapper to prevent nil table errors
]]
function WarbandNexus:IsUsingOtherBankAddon()
    if not self.db or not self.db.profile or not self.db.profile.bankConflictChoices then
        return false
    end
    
    for addonName, choice in pairs(self.db.profile.bankConflictChoices) do
        if choice == "useOther" then
            return true
        end
    end
    
    return false
end

--[[
    Clear conflict cache (call this after disabling an addon)
]]
function WarbandNexus:ClearConflictCache()
    self._conflictCheckCache = nil
end

--[[
    Disable conflicting addon's bank module
    @param addonName string - Name of conflicting addon
    @return boolean success, string message
]]
function WarbandNexus:DisableConflictingBankModule(addonName)
    if not addonName or addonName == "" then
        return false, "Unknown addon. Please disable manually."
    end
    
    -- ElvUI special handling - disable only bags module, not entire addon
    if addonName == "ElvUI" then
        -- Check if ElvUI is loaded
        if ElvUI then
            local E = ElvUI[1]
            if E then
                -- Method 1: Disable per-profile setting
                if E.db and E.db.bags then
                    E.db.bags.enabled = false
                end
                
                -- Method 2: Disable global setting (CRITICAL!)
                if E.private and E.private.bags then
                    E.private.bags.enable = false
                end
                
                -- Method 3: Try to disable module directly via ElvUI API
                if E.DisableModule then
                    pcall(function() E:DisableModule('Bags') end)
                end
                
                -- Method 4: Disable bags in ALL profiles (fallback)
                if E.data and E.data.profiles then
                    for profileName, profileData in pairs(E.data.profiles) do
                        if profileData.bags then
                            profileData.bags.enabled = false
                        end
                    end
                end
                
                -- Mark that bags module was disabled in our own DB
                if not self.db.profile.elvuiModuleStates then
                    self.db.profile.elvuiModuleStates = {}
                end
                self.db.profile.elvuiModuleStates.bagsDisabled = true
                
                self:Print("|cff00ff00ElvUI Bags module disabled successfully!|r")
                return true, "ElvUI Bags module disabled. Please /reload to apply changes."
            end
        end
        
        -- Fallback if ElvUI not accessible yet
        return true, "ElvUI bags will be disabled. Please /reload to apply changes."
    end
    
    -- Bagnon, Combuctor, AdiBags, etc. - disable entire addon
    local DisableAddon = C_AddOns and C_AddOns.DisableAddOn or DisableAddOn
    DisableAddon(addonName)
    return true, string.format("%s disabled. Please /reload to apply changes.", addonName)
end

--[[
    Enable conflicting addon's bank module (when user chooses to use it)
    @param addonName string - Name of conflicting addon
    @return boolean success, string message
]]
function WarbandNexus:EnableConflictingBankModule(addonName)
    if not addonName then
        return false, "No addon name provided"
    end
    
    -- ElvUI special handling - enable bags module only
    if addonName == "ElvUI" then
        if ElvUI then
            local E = ElvUI[1]
            if E then
                -- Method 1: Enable per-profile setting
                if E.db and E.db.bags then
                    E.db.bags.enabled = true
                end
                
                -- Method 2: Enable global setting (CRITICAL!)
                if E.private and E.private.bags then
                    E.private.bags.enable = true
                end
                
                -- Method 3: Try to enable module directly via ElvUI API
                if E.EnableModule then
                    pcall(function() E:EnableModule('Bags') end)
                end
                
                -- Method 4: Enable bags in ALL profiles (fallback)
                if E.data and E.data.profiles then
                    for profileName, profileData in pairs(E.data.profiles) do
                        if profileData.bags then
                            profileData.bags.enabled = true
                        end
                    end
                end
                
                -- Clear disabled state in our own DB
                if self.db.profile.elvuiModuleStates then
                    self.db.profile.elvuiModuleStates.bagsDisabled = false
                end
                
                self:Print("|cff00ff00ElvUI Bags module enabled successfully!|r")
                return true, "ElvUI Bags module enabled. Please /reload to apply changes."
            end
        end
        
        return true, "ElvUI bags will be enabled. Please /reload to apply changes."
    end
    
    -- Other addons - enable entire addon
    local EnableAddon = C_AddOns and C_AddOns.EnableAddOn or EnableAddOn
    EnableAddon(addonName)
    return true, string.format("%s enabled. Please /reload to apply changes.", addonName)
end

--[[
    Show bank addon conflict warning popup with disable option
    @param addonName string - Name of conflicting addon
]]
function WarbandNexus:QueueConflictPopup(addonName)
    if not self._conflictQueue then
        self._conflictQueue = {}
    end
    table.insert(self._conflictQueue, addonName)
end

function WarbandNexus:ShowNextConflictPopup()
    if not self._conflictQueue then
        self._conflictQueue = {}
    end
    
    if self._isProcessingConflict or #self._conflictQueue == 0 then
        return
    end
    
    self._isProcessingConflict = true
    local addonName = table.remove(self._conflictQueue, 1)
    self:ShowBankAddonConflictWarning(addonName)
end

function WarbandNexus:CheckBankConflictsOnLogin()
    -- Throttle: Don't check more than once every 1 second
    -- Prevents duplicate popups from multiple triggers (OnEnable, OnPlayerEnteringWorld, etc.)
    local now = time()
    if self._lastConflictCheck and (now - self._lastConflictCheck) < 1 then
        return
    end
    self._lastConflictCheck = now
    
    -- Don't interrupt an ongoing conflict resolution
    if self._isProcessingConflict then
        return
    end
    
    -- Initialize flags
    self._needsReload = false
    
    -- Safety check: Ensure db is initialized
    if not self.db or not self.db.profile or not self.db.profile.bankConflictChoices then
        return
    end
    
    -- Skip if bank module is disabled
    if not self.db.profile.bankModuleEnabled then
        return
    end
    
    -- Detect all conflicting addons
    local conflicts = self:DetectBankAddonConflicts()
    
    if not conflicts or #conflicts == 0 then
        return -- No conflicts
    end
    
    -- Filter out addons that user already made a choice for
    -- Note: Choices are already reset in OnEnable/OnBankOpened if user re-enabled addons
    local unresolvedConflicts = {}
    for _, addonName in ipairs(conflicts) do
        local choice = self.db.profile.bankConflictChoices[addonName]
        
        -- Show popup if:
        -- 1. No choice exists yet (first time, or choice was reset due to re-enable)
        -- 2. User previously chose "useWarband" but addon is still detected
        --    (This shouldn't happen if our disable logic works, but safe fallback)
        if not choice then
            -- No choice = need to ask user
            table.insert(unresolvedConflicts, addonName)
        elseif choice == "useWarband" then
            -- User chose Warband but addon still detected (shouldn't happen normally)
            -- This is a safety net in case disable failed
            table.insert(unresolvedConflicts, addonName)
        end
        -- Skip if choice == "useOther" (user wants to keep the other addon)
    end
    
    if #unresolvedConflicts == 0 then
        return -- All conflicts already resolved
    end
    
    self:Print("|cffffaa00Showing conflict popup for " .. #unresolvedConflicts .. " addon(s)|r")
    
    -- Queue all unresolved conflicts
    for _, addonName in ipairs(unresolvedConflicts) do
        self:QueueConflictPopup(addonName)
    end
    
    -- Start showing popups
    self:ShowNextConflictPopup()
end

function WarbandNexus:ShowReloadPopup()
    -- Create reload confirmation popup
    StaticPopupDialogs["WARBANDNEXUS_RELOAD_UI"] = {
        text = "|cff00ff00Addon settings changed!|r\n\nA UI reload is required to apply changes.\n\nReload now?",
        button1 = "Reload",
        button2 = "Later",
        OnAccept = function()
            -- Use C_UI.Reload() (not protected, safe for addons in TWW 11.0+)
            if C_UI and C_UI.Reload then
                C_UI.Reload()
            else
                -- Fallback for older clients (may cause taint warning)
                ReloadUI()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    StaticPopup_Show("WARBANDNEXUS_RELOAD_UI")
end

function WarbandNexus:ShowBankAddonConflictWarning(addonName)
    -- Create or update popup dialog
    StaticPopupDialogs["WARBANDNEXUS_BANK_CONFLICT"] = {
        text = "",
        button1 = "Use Warband Nexus",
        button2 = "Use " .. addonName,
        OnAccept = function(self)
            -- Button 1: User wants to use Warband Nexus - disable conflicting addon
            local addonName = self.data
            WarbandNexus.db.profile.bankConflictChoices[addonName] = "useWarband"
            
            local success, message = WarbandNexus:DisableConflictingBankModule(addonName)
            if not success then
                WarbandNexus:Print(message)
            end
            
            -- Mark that we need reload (if addon was disabled)
            if success then
                -- Track that we disabled this addon
                WarbandNexus.db.profile.toggledAddons[addonName] = "disabled"
                WarbandNexus._needsReload = true
                WarbandNexus:ClearConflictCache()
            end
            
            WarbandNexus._isProcessingConflict = false
            
            -- Process next conflict OR reload if no more conflicts
            if #WarbandNexus._conflictQueue > 0 then
                -- More conflicts to resolve (small delay for UX)
                C_Timer.After(0.3, function()
                    if WarbandNexus then
                        WarbandNexus:ShowNextConflictPopup()
                    end
                end)
            elseif WarbandNexus._needsReload then
                -- All done, show reload popup
                WarbandNexus:ShowReloadPopup()
            end
        end,
        OnCancel = function(self)
            -- Button 2: User wants to keep the other addon
            local addonName = self.data
            WarbandNexus.db.profile.bankConflictChoices[addonName] = "useOther"
            
            -- NEW: Automatically disable bank module since user chose other addon
            WarbandNexus.db.profile.bankModuleEnabled = false
            
            -- Track that user chose this addon (it's already enabled)
            WarbandNexus.db.profile.toggledAddons[addonName] = "enabled"
            
            WarbandNexus:Print(string.format(
                "|cff00ff00Using %s for bank UI.|r Warband Nexus will run in background mode (data tracking only).",
                addonName
            ))
            
            -- Enable the conflicting addon (make sure it's active)
            local success, message = WarbandNexus:EnableConflictingBankModule(addonName)
            if success then
                WarbandNexus._needsReload = true
            end
            
            WarbandNexus._isProcessingConflict = false
            
            -- Process next conflict OR finish if no more conflicts
            if #WarbandNexus._conflictQueue > 0 then
                -- More conflicts to resolve (small delay for UX)
                C_Timer.After(0.3, function()
                    if WarbandNexus then
                        WarbandNexus:ShowNextConflictPopup()
                    end
                end)
            elseif WarbandNexus._needsReload then
                -- Some addons were enabled/disabled, show reload popup
                WarbandNexus:ShowReloadPopup()
            else
                -- All done, no reload needed
                WarbandNexus:Print("|cff00ff00All conflicts resolved! No reload needed.|r")
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false, -- Force user to choose
        preferredIndex = 3,
    }
    
    -- Set dynamic text
    local warningText
    
    -- ElvUI special message (only bags module will be disabled)
    if addonName == "ElvUI" then
        warningText = string.format(
            "|cffff9900Bank Addon Conflict|r\n\n" ..
            "You have |cff00ccff%s|r installed.\n\n" ..
            "Which addon do you want to use for bank UI?\n\n" ..
            "|cff00ff00Use Warband Nexus:|r Disable ElvUI |cffaaaaaa(Bags module only)|r\n" ..
            "|cff888888Use %s:|r WarbandNexus works in background mode\n\n" ..
            "|cff00ff00Note:|r Only the ElvUI Bags module will be disabled,\n" ..
            "not the entire ElvUI addon.\n\n" ..
            "Characters, PvE, and Statistics tabs work regardless of choice.",
            addonName, addonName
        )
    else
        -- Generic message for other addons
        warningText = string.format(
            "|cffff9900Bank Addon Conflict|r\n\n" ..
            "You have |cff00ccff%s|r installed.\n\n" ..
            "Which addon do you want to use for bank UI?\n\n" ..
            "|cff00ff00Use Warband Nexus:|r Disable %s automatically\n" ..
            "|cff888888Use %s:|r WarbandNexus works in background mode\n\n" ..
            "Characters, PvE, and Statistics tabs work regardless of choice.",
            addonName, addonName, addonName
        )
    end
    
    StaticPopupDialogs["WARBANDNEXUS_BANK_CONFLICT"].text = warningText
    local dialog = StaticPopup_Show("WARBANDNEXUS_BANK_CONFLICT")
    if dialog then
        dialog.data = addonName
    end
end

-- Setup BankFrame hook to make it invisible (but NOT hidden - keeps API working!)
function WarbandNexus:SetupBankFrameHook()
    if not BankFrame then return end
    if self.bankFrameHooked then return end
    if self:IsUsingOtherBankAddon() then return end
    
    -- Hook OnShow to re-suppress if Blizzard tries to show the frame
    BankFrame:HookScript("OnShow", function()
        if WarbandNexus and WarbandNexus.bankFrameSuppressed then
            WarbandNexus:SuppressDefaultBankFrame()
        end
    end)
    
    self.bankFrameHooked = true
end

-- Suppress Blizzard Bank UI (hide it completely)
function WarbandNexus:SuppressDefaultBankFrame()
    if not BankFrame then return end
    if self:IsUsingOtherBankAddon() then return end
    
    self.bankFrameSuppressed = true
    
    -- Hide BankFrame (visual only - DON'T use :Hide(), it triggers BANKFRAME_CLOSED!)
    BankFrame:SetAlpha(0)
    BankFrame:EnableMouse(false)
    BankFrame:ClearAllPoints()
    BankFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, 10000)
    
    -- TWW FIX: Hide global BankPanel (this is what you actually see in TWW)
    if BankPanel then
        BankPanel:SetAlpha(0)
        BankPanel:EnableMouse(false)
        BankPanel:ClearAllPoints()
        BankPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, 10000)
        
        -- Recursively hide all BankPanel children (visual only)
        local function HideAllChildren(frame)
            local children = { frame:GetChildren() }
            for _, child in ipairs(children) do
                if child then
                    pcall(function()
                        child:SetAlpha(0)
                        child:EnableMouse(false)
                        HideAllChildren(child)
                    end)
                end
            end
        end
        HideAllChildren(BankPanel)
    end
end

-- Suppress Guild Bank UI
function WarbandNexus:SuppressGuildBankFrame()
    if not GuildBankFrame then return end
    if self:IsUsingOtherBankAddon() then return end
    
    self.guildBankFrameSuppressed = true
    
    -- Hide GuildBankFrame (visual only - DON'T use :Hide()!)
    GuildBankFrame:SetAlpha(0)
    GuildBankFrame:EnableMouse(false)
    GuildBankFrame:ClearAllPoints()
    GuildBankFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, 10000)
end

-- Restore Guild Bank UI
function WarbandNexus:RestoreGuildBankFrame()
    if not GuildBankFrame then return end
    if self:IsUsingOtherBankAddon() then return end
    
    self.guildBankFrameSuppressed = false
    
    -- Restore GuildBankFrame
    GuildBankFrame:SetAlpha(1)
    GuildBankFrame:EnableMouse(true)
    GuildBankFrame:ClearAllPoints()
    GuildBankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    GuildBankFrame:Show()
    
    self:Print("Guild Bank UI restored")
end

-- Restore Blizzard Bank UI (show it again)
function WarbandNexus:RestoreDefaultBankFrame()
    if not BankFrame then return end
    if self:IsUsingOtherBankAddon() then return end
    
    self.bankFrameSuppressed = false
    
    -- Restore BankFrame
    BankFrame:SetAlpha(1)
    BankFrame:EnableMouse(true)
    BankFrame:ClearAllPoints()
    BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    BankFrame:Show()
    
    -- TWW FIX: Restore global BankPanel
    if BankPanel then
        BankPanel:SetAlpha(1)
        BankPanel:EnableMouse(true)
        BankPanel:Show()
        BankPanel:ClearAllPoints()
        BankPanel:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 0, 0)
        
        -- Recursively show all BankPanel children
        local function ShowAllChildren(frame)
            local children = { frame:GetChildren() }
            for _, child in ipairs(children) do
                if child then
                    pcall(function()
                        child:SetAlpha(1)
                        child:Show()
                        child:EnableMouse(true)
                        ShowAllChildren(child)
                    end)
                end
            end
        end
        ShowAllChildren(BankPanel)
    end
    
    self:Print("Blizzard Bank UI restored")
end

-- Show the default Blizzard bank frame (Classic Bank button)
function WarbandNexus:ShowDefaultBankFrame()
    self:RestoreDefaultBankFrame()
    
    if OpenAllBags then
        OpenAllBags()
    end
end

function WarbandNexus:OnBankClosed()
    self.bankIsOpen = false
    self.warbandBankIsOpen = false
    
    -- If user was using Classic Bank mode, hide bank again
    if self.classicBankMode then
        self.classicBankMode = false
        self:SuppressDefaultBankFrame()
    else
        -- Normal bank close (addon was already visible)
    -- Show warning if addon window is open
    if self:IsMainWindowShown() then
        -- Refresh title/status immediately
        if self.UpdateStatus then
             self:UpdateStatus()
        end
        self:Print("|cffff9900Bank connection lost. Showing cached data.|r")
    end
    
    -- Refresh UI if open (to update buttons/status)
    if self.RefreshUI then
        self:RefreshUI()
        end
    end
end

-- Guild Bank Opened Handler
function WarbandNexus:OnGuildBankOpened()
    self.guildBankIsOpen = true
    self.currentBankType = "guild"
    
    -- Suppress Blizzard's Guild Bank frame if not using another addon
    if not self:IsUsingOtherBankAddon() then
        self:SuppressGuildBankFrame()
        
        -- Open main window to Guild Bank tab
        if self.ShowMainWindow then
            self:ShowMainWindow()
            -- Switch to Guild Bank tab (will be implemented in UI module)
            if self.SwitchBankTab then
                self:SwitchBankTab("guild")
            end
        end
    end
    
    -- Scan guild bank
    if self.db.profile.autoScan and self.ScanGuildBank then
        C_Timer.After(0.3, function()
            if WarbandNexus and WarbandNexus.ScanGuildBank then
                WarbandNexus:ScanGuildBank()
            end
        end)
    end
    
    -- Refresh UI
    if self.RefreshUI then
        self:RefreshUI()
    end
end

-- Guild Bank Closed Handler
function WarbandNexus:OnGuildBankClosed()
    self.guildBankIsOpen = false
    
    -- Show warning if addon window is open
    if self:IsMainWindowShown() then
        if self.UpdateStatus then
            self:UpdateStatus()
        end
        self:Print("|cffff9900Guild Bank connection lost. Showing cached data.|r")
    end
    
    -- Refresh UI if open
    if self.RefreshUI then
        self:RefreshUI()
    end
end

-- Check if main window is visible
function WarbandNexus:IsMainWindowShown()
    local UI = self.UI
    if UI and UI.mainFrame and UI.mainFrame:IsShown() then
        return true
    end
    -- Fallback check
    if WarbandNexusMainFrame and WarbandNexusMainFrame:IsShown() then
        return true
    end
    return false
end

-- Called when player or Warband Bank gold changes (PLAYER_MONEY, ACCOUNT_MONEY)
function WarbandNexus:OnMoneyChanged()
    self.db.char.lastKnownGold = GetMoney()
    
    -- Update character gold in global tracking
    self:UpdateCharacterGold()
    
    -- INSTANT UI refresh if addon window is open
    if self.bankIsOpen and self.RefreshUI then
        -- Use very short delay to batch multiple money events
        if not self.moneyRefreshPending then
            self.moneyRefreshPending = true
            C_Timer.After(0.05, function()
                self.moneyRefreshPending = false
                if WarbandNexus and WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end)
        end
    end
end

--[[
    Called when currency changes
]]
function WarbandNexus:OnCurrencyChanged()
    -- Update currency data in background
    if self.UpdateCurrencyData then
        self:UpdateCurrencyData()
    end
    
    -- INSTANT UI refresh if currency tab is open
    local mainFrame = self.UI and self.UI.mainFrame
    if mainFrame and mainFrame.currentTab == "currency" and self.RefreshUI then
        -- Use short delay to batch multiple currency events
        if not self.currencyRefreshPending then
            self.currencyRefreshPending = true
            C_Timer.After(0.1, function()
                self.currencyRefreshPending = false
                if WarbandNexus and WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end)
        end
    end
end

--[[
    Called when reputation changes
    Scan and update reputation data
]]
function WarbandNexus:OnReputationChanged()
    -- Scan reputations in background
    if self.ScanReputations then
        self.currentTrigger = "UPDATE_FACTION"
        self:ScanReputations()
    end
    
    -- Send message for cache invalidation
    self:SendMessage("WARBAND_REPUTATIONS_UPDATED")
    
    -- INSTANT UI refresh if reputation tab is open
    local mainFrame = self.UI and self.UI.mainFrame
    if mainFrame and mainFrame.currentTab == "reputations" and self.RefreshUI then
        -- Use short delay to batch multiple reputation events
        if not self.reputationRefreshPending then
            self.reputationRefreshPending = true
            C_Timer.After(0.2, function()
                self.reputationRefreshPending = false
                if WarbandNexus and WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end)
        end
    end
end

--[[
    Called when M+ dungeon run completes
    Update PvE cache with new data
]]
function WarbandNexus:CHALLENGE_MODE_COMPLETED(mapChallengeModeID, level, time, onTime, keystoneUpgradeLevels)
    -- Re-collect PvE data for current character
    local pveData = self:CollectPvEData()
    
    -- Update cache
    local key = self:GetCharacterKey()
    if self.db.global.characters[key] then
        self.db.global.characters[key].pve = pveData
        self.db.global.characters[key].lastSeen = time()
    end
    
    -- Refresh UI if PvE tab is visible
    if self.UI and self.UI.activeTab == "pve" then
        self:RefreshUI()
    end
end

--[[
    Called when new weekly M+ record is set
    Update PvE cache with new data
]]
function WarbandNexus:MYTHIC_PLUS_NEW_WEEKLY_RECORD()
    -- Same logic as CHALLENGE_MODE_COMPLETED
    self:CHALLENGE_MODE_COMPLETED()
end

--[[
    Called when an addon is loaded
    Check if it's a conflicting bank addon that user previously disabled
]]
function WarbandNexus:OnAddonLoaded(event, addonName)
    if not self.db or not self.db.profile or not self.db.profile.bankConflictChoices then
        return
    end
    
    -- List of known conflicting addons
    local conflictingAddons = {
        "Bagnon", "Combuctor", "ArkInventory", "AdiBags", "Baganator",
        "LiteBag", "TBag", "BaudBag", "Inventorian",
        "ElvUI_Bags", "ElvUI",
        "BankStack", "BankItems", "Sorted",
        "BankUI", "InventoryManager", "BagAddon", "BankModifier",
        "CustomBank", "AdvancedInventory", "BagSystem"
    }
    
    -- Check if this is a conflicting addon
    local isConflicting = false
    for _, conflictAddon in ipairs(conflictingAddons) do
        if addonName == conflictAddon then
            isConflicting = true
            break
        end
    end
    
    if not isConflicting then
        return -- Not a conflicting addon
    end
    
    -- Check if user previously chose "useWarband" for this addon
    local previousChoice = self.db.profile.bankConflictChoices[addonName]
    
    if previousChoice == "useWarband" then
        -- User re-enabled an addon they previously disabled
        -- Reset choice and show popup after a delay
        
        -- Reset the choice so popup will show
        self.db.profile.bankConflictChoices[addonName] = nil
        
        -- Show conflict popup after brief delay (addon needs to fully initialize)
        C_Timer.After(2, function()
            if WarbandNexus and WarbandNexus.CheckBankConflictsOnLogin then
                -- CheckBankConflictsOnLogin has throttling, safe to call
                WarbandNexus:CheckBankConflictsOnLogin()
            end
        end)
    end
end

--[[
    Called when player enters the world (login or reload)
]]
function WarbandNexus:OnPlayerEnteringWorld(event, isInitialLogin, isReloadingUi)
    -- Check for notifications on initial login only (not on reload)
    if isInitialLogin and self.CheckNotificationsOnLogin then
        self:CheckNotificationsOnLogin()
    end
    
    -- Scan reputations on login (after 3 seconds to ensure API is ready)
    C_Timer.After(3, function()
        if WarbandNexus and WarbandNexus.ScanReputations then
            WarbandNexus.currentTrigger = "PLAYER_LOGIN"
            WarbandNexus:ScanReputations()
        end
    end)
    
    -- Initialize plan tracking for completion notifications (only on initial login)
    if isInitialLogin then
        C_Timer.After(4, function()
            if WarbandNexus and WarbandNexus.InitializePlanTracking then
                WarbandNexus:InitializePlanTracking()
            end
        end)
    end
    
    -- NOTE: Character save is now handled by raw frame event handler in OnInitialize()
    -- This ensures early event capture before AceEvent is fully initialized
    
    -- CRITICAL: Secondary conflict check after longer delay
    -- This catches addons that load late (ElvUI modules, etc.)
    -- Runs BOTH on initial login AND reload to ensure nothing is missed
    if isInitialLogin or isReloadingUi then
        C_Timer.After(3, function()
            if WarbandNexus and WarbandNexus.CheckBankConflictsOnLogin then
                -- This is a safety net in case OnEnable check was too early
                WarbandNexus:CheckBankConflictsOnLogin()
            end
        end)
        
        -- Extra check after 6 seconds for very late-loading addons
        C_Timer.After(6, function()
            if WarbandNexus and WarbandNexus.CheckBankConflictsOnLogin then
                -- Final safety check
                WarbandNexus:CheckBankConflictsOnLogin()
            end
        end)
    end
end

--[[
    Called when player levels up
]]
function WarbandNexus:OnPlayerLevelUp(event, level)
    -- Force update on level up
    self.characterSaved = false
    self:SaveCharacter()
end

--[[
    Called when combat starts (PLAYER_REGEN_DISABLED)
    Hides UI to prevent taint issues
]]
function WarbandNexus:OnCombatStart()
    -- Hide main UI during combat (taint protection)
    if self.mainFrame and self.mainFrame:IsShown() then
        self.mainFrame:Hide()
        self._hiddenByCombat = true
        self:Print("|cffff6600UI hidden during combat.|r")
    end
end

--[[
    Called when combat ends (PLAYER_REGEN_ENABLED)
    Restores UI if it was hidden by combat
]]
function WarbandNexus:OnCombatEnd()
    -- Restore UI after combat if it was hidden by combat
    if self._hiddenByCombat then
        if self.mainFrame then
            self.mainFrame:Show()
        end
        self._hiddenByCombat = false
    end
end

--[[
    Called when PvE data changes (Great Vault, Lockouts, M+ completion)
]]
function WarbandNexus:OnPvEDataChanged()
    -- Re-collect and update PvE data for current character
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        local pveData = self:CollectPvEData()
        self.db.global.characters[key].pve = pveData
        self.db.global.characters[key].lastSeen = time()
        
        -- Invalidate PvE cache for current character
        if self.InvalidatePvECache then
            self:InvalidatePvECache(key)
        end
        
        -- Refresh UI if PvE tab is open
        if self.RefreshPvEUI then
            self:RefreshPvEUI()
        end
    end
end

--[[
    Called when keystone might have changed (delayed bag update)
]]
function WarbandNexus:OnKeystoneChanged()
    -- Throttle keystone checks to avoid spam
    if not self.keystoneCheckPending then
        self.keystoneCheckPending = true
        C_Timer.After(0.5, function()
            self.keystoneCheckPending = false
            
            -- Update PvE data (existing behavior)
            if WarbandNexus and WarbandNexus.OnPvEDataChanged then
                WarbandNexus:OnPvEDataChanged()
            end
            
            -- Update mythic keystone data
            if WarbandNexus then
                local name = UnitName("player")
                local realm = GetRealmName()
                local key = name .. "-" .. realm
                
                if WarbandNexus.db and WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[key] then
                    -- Scan for keystone
                    local keystoneData = nil
                    if WarbandNexus.ScanMythicKeystone then
                        keystoneData = WarbandNexus:ScanMythicKeystone()
                    end
                    
                    -- Update in database
                    WarbandNexus.db.global.characters[key].mythicKey = keystoneData
                    WarbandNexus.db.global.characters[key].lastSeen = time()
                    
                    -- Invalidate cache to refresh UI
                    if WarbandNexus.InvalidateCharacterCache then
                        WarbandNexus:InvalidateCharacterCache()
                    end
                end
            end
        end)
    end
end

--[[
    Event handler for collection changes (mounts, pets, toys)
    Ultra-fast update with minimal throttle for instant UI feedback
]]
function WarbandNexus:OnCollectionChanged(event)
    -- Minimal throttle only for TOYS_UPDATED (can fire frequently)
    -- NEW_* events are single-fire, no throttle needed
    local needsThrottle = (event == "TOYS_UPDATED")
    
    if needsThrottle and self.collectionCheckPending then
        return -- Skip if throttled
    end
    
    if needsThrottle then
        self.collectionCheckPending = true
        C_Timer.After(0.2, function()
            if WarbandNexus then
                WarbandNexus.collectionCheckPending = false
            end
        end)
    end
    
    -- Update character data
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        -- Update timestamp
        self.db.global.characters[key].lastSeen = time()
        
        -- Invalidate collection cache (data changed)
        if self.InvalidateCollectionCache then
            self:InvalidateCollectionCache()
        end
        
        -- INSTANT UI refresh if Statistics tab is active
        if self.UI and self.UI.mainFrame then
            local mainFrame = self.UI.mainFrame
            if mainFrame:IsShown() and mainFrame.currentTab == "stats" then
                if self.RefreshUI then
                    self:RefreshUI()
                end
            end
        end
    end
end

--[[
    Event handler for pet journal changes (cage/release)
    Smart tracking: Only update when pet count actually changes
]]
function WarbandNexus:OnPetListChanged()
    -- Only process if UI is open on stats tab
    if not self.UI or not self.UI.mainFrame then return end
    
    local mainFrame = self.UI.mainFrame
    if not mainFrame:IsShown() or mainFrame.currentTab ~= "stats" then
        return -- Skip if UI not visible or wrong tab
    end
    
    -- Get current pet count
    local _, currentPetCount = C_PetJournal.GetNumPets()
    
    -- Initialize cache if needed
    if not self.lastPetCount then
        self.lastPetCount = currentPetCount
        return -- First call, just cache
    end
    
    -- Check if count actually changed
    if currentPetCount == self.lastPetCount then
        return -- No change, skip update
    end
    
    -- Count changed! Update cache
    self.lastPetCount = currentPetCount
    
    -- Throttle to batch rapid changes
    if self.petListCheckPending then return end
    
    self.petListCheckPending = true
    C_Timer.After(0.3, function()
        if not WarbandNexus then return end
        WarbandNexus.petListCheckPending = false
        
        -- Update timestamp
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[key] then
            WarbandNexus.db.global.characters[key].lastSeen = time()
            
            -- Instant UI refresh
            if WarbandNexus.RefreshUI then
                WarbandNexus:RefreshUI()
            end
        end
    end)
end

-- SaveCurrentCharacterData() moved to Modules/DataService.lua


-- UpdateCharacterGold() moved to Modules/DataService.lua

-- CollectPvEData() moved to Modules/DataService.lua


-- GetAllCharacters() moved to Modules/DataService.lua

---@param bagIDs table Table of bag IDs that were updated
function WarbandNexus:OnBagUpdate(bagIDs)
    
    -- Check if bank is open at all
    if not self.bankIsOpen then return end
    
    local warbandUpdated = false
    local personalUpdated = false
    local inventoryUpdated = false
    
    for bagID in pairs(bagIDs) do
        
        -- Check Warband bags
        if self:IsWarbandBag(bagID) then
            warbandUpdated = true
        end
        -- Check Personal bank bags (including main bank -1 and bags 6-12)
        if bagID == -1 or (bagID >= 6 and bagID <= 12) then
            personalUpdated = true
        end
        -- Check player inventory bags (0-4) - item moved TO inventory
        if bagID >= 0 and bagID <= 4 then
            inventoryUpdated = true
        end
    end
    
    
    -- If inventory changed while bank is open, we need to re-scan banks too
    -- (item may have been moved from bank to inventory)
    local needsRescan = warbandUpdated or personalUpdated or inventoryUpdated
    
    -- Batch updates with a timer to avoid spam
    if needsRescan then
        if self.pendingScanTimer then
            self:CancelTimer(self.pendingScanTimer)
        end
        self.pendingScanTimer = self:ScheduleTimer(function()
            
            -- Re-scan both banks when any change occurs (items can move between them)
            if self.warbandBankIsOpen and self.ScanWarbandBank then
                self:ScanWarbandBank()
            end
            if self.bankIsOpen and self.ScanPersonalBank then
                self:ScanPersonalBank()
            end
            
            -- Invalidate item caches (data changed)
            if self.InvalidateItemCache then
                self:InvalidateItemCache()
            end
            
            -- Invalidate tooltip cache (items changed)
            if self.InvalidateTooltipCache then
                self:InvalidateTooltipCache()
            end
            
            -- Refresh UI
            if self.RefreshUI then
                self:RefreshUI()
            end
            
            
            self.pendingScanTimer = nil
        end, 0.5)
    end
end

--[[
    Utility Functions
]]

---Check if a bag ID is a Warband bank bag
---@param bagID number The bag ID to check
---@return boolean
function WarbandNexus:IsWarbandBag(bagID)
    for _, warbandBagID in ipairs(ns.WARBAND_BAGS) do
        if bagID == warbandBagID then
            return true
        end
    end
    return false
end

---Check if Warband bank is currently open
---Uses event-based tracking combined with bag access verification
---@return boolean
function WarbandNexus:IsWarbandBankOpen()
    -- Primary method: Use our tracked state from BANKFRAME events
    if self.warbandBankIsOpen then
        return true
    end
    
    -- Secondary method: If bank event flag is set, verify we can access Warband bags
    if self.bankIsOpen then
        local firstBagID = Enum.BagIndex.AccountBankTab_1
        if firstBagID then
            local numSlots = C_Container.GetContainerNumSlots(firstBagID)
            if numSlots and numSlots > 0 then
                -- We can access Warband bank, update flag
                self.warbandBankIsOpen = true
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
            -- Try to verify by checking if BankFrame exists and is shown
            if BankFrame and BankFrame:IsShown() then
                self.warbandBankIsOpen = true
                self.bankIsOpen = true
                return true
            end
        end
    end
    
    return false
end

---Get the number of slots in a bag (with fallback)
---@param bagID number The bag ID
---@return number
function WarbandNexus:GetBagSize(bagID)
    -- Use API wrapper for future-proofing
    return self:API_GetBagSize(bagID)
end

---Debug function (disabled for production)
---@param message string The message to print
function WarbandNexus:Debug(message)
    if self.db and self.db.profile and self.db.profile.debugMode then
        self:Print("|cff888888[DEBUG]|r " .. tostring(message))
    end
end

---Get display name for an item (handles caged pets)
---Caged pets show "Pet Cage" in item name but have the real pet name in tooltip line 3
---@param itemID number The item ID
---@param itemName string The item name from cache
---@param classID number|nil The item class ID (17 = Battle Pet)
---@return string displayName The display name (pet name for caged pets, item name otherwise)
function WarbandNexus:GetItemDisplayName(itemID, itemName, classID)
    -- If this is a caged pet (classID 17), try to get the pet name from tooltip
    if classID == 17 and itemID then
        local petName = self:GetPetNameFromTooltip(itemID)
        if petName then
            return petName
        end
    end
    
    -- Fallback: Use item name
    return itemName or "Unknown Item"
end

---Extract pet name from item tooltip (locale-independent)
---Used for caged pets where item name is "Pet Cage" but tooltip has the real pet name
---@param itemID number The item ID
---@return string|nil petName The pet's name extracted from tooltip
function WarbandNexus:GetPetNameFromTooltip(itemID)
    if not itemID then
        return nil
    end
    
    -- METHOD 1: Try C_PetJournal API first (most reliable)
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local result = C_PetJournal.GetPetInfoByItemID(itemID)
        
        -- If result is a number, it's speciesID (old behavior)
        if type(result) == "number" and result > 0 then
            local speciesName = C_PetJournal.GetPetInfoBySpeciesID(result)
            if speciesName and speciesName ~= "" then
                return speciesName
            end
        end
        
        -- If result is a string, it's the pet name (TWW behavior)
        if type(result) == "string" and result ~= "" then
            return result
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
    
    -- Caged pet tooltip structure (TWW):
    -- Line 1: Item name ("Pet Cage" / "BattlePet")
    -- Line 2: Category ("Battle Pet")
    -- Line 3: Pet's actual name OR empty OR quality/level
    -- Line 4+: Stats or "Use:" description
    
    -- Strategy: Find first line that:
    -- 1. Is NOT the item name
    -- 2. Is NOT "Battle Pet" or translations
    -- 3. Does NOT contain ":"
    -- 4. Is NOT quality/level info
    -- 5. Is a reasonable name length (3-35 chars)
    
    local knownBadPatterns = {
        "^Battle Pet",      -- Category (EN)
        "^BattlePet",       -- Item name
        "^Pet Cage",        -- Item name
        "^Kampfhaustier",   -- Category (DE)
        "^Mascotte",        -- Category (FR)
        "^Companion",       -- Old category
        "^Use:",            -- Description
        "^Requires:",       -- Requirement
        "Level %d",         -- Level info
        "^Poor",            -- Quality
        "^Common",          -- Quality
        "^Uncommon",        -- Quality
        "^Rare",            -- Quality
        "^Epic",            -- Quality
        "^Legendary",       -- Quality
        "^%d+$",            -- Just numbers
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

--[[
    Placeholder functions for modules
    These will be implemented in their respective module files
]]

function WarbandNexus:ScanWarbandBank()
    -- Implemented in Modules/Scanner.lua
end

function WarbandNexus:ToggleMainWindow()
    -- Implemented in Modules/UI.lua
end

function WarbandNexus:OpenDepositQueue()
    -- Implemented in Modules/Banker.lua
end

function WarbandNexus:SearchItems(searchTerm)
    -- Implemented in Modules/UI.lua
end

function WarbandNexus:RefreshUI()
    -- Implemented in Modules/UI.lua
end

function WarbandNexus:RefreshPvEUI()
    -- Force refresh of PvE tab if currently visible (instant)
    if self.UI and self.UI.mainFrame then
        local mainFrame = self.UI.mainFrame
        if mainFrame:IsShown() and mainFrame.currentTab == "pve" then
            -- Instant refresh for responsive UI
            if self.RefreshUI then
                self:RefreshUI()
            end
        end
    end
end

function WarbandNexus:OpenOptions()
    -- Will be properly implemented in Config.lua
    Settings.OpenToCategory(ADDON_NAME)
end

---Print bank debug information to help diagnose detection issues
function WarbandNexus:PrintBankDebugInfo()
    self:Print("=== Bank Debug Info ===")
    
    -- Internal state flags
    self:Print("Internal Flags:")
    self:Print("  self.bankIsOpen: " .. tostring(self.bankIsOpen))
    self:Print("  self.warbandBankIsOpen: " .. tostring(self.warbandBankIsOpen))
    
    -- BankFrame check
    self:Print("BankFrame:")
    self:Print("  exists: " .. tostring(BankFrame ~= nil))
    if BankFrame then
        self:Print("  IsShown: " .. tostring(BankFrame:IsShown()))
    end
    
    -- Bag slot check (most reliable)
    self:Print("Warband Bank Bags:")
    for i = 1, 5 do
        local bagID = Enum.BagIndex["AccountBankTab_" .. i]
        if bagID then
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            local itemCount = 0
            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bagID, slot)
                    if info and info.itemID then
                        itemCount = itemCount + 1
                    end
                end
            end
            self:Print("  Tab " .. i .. ": BagID=" .. bagID .. ", Slots=" .. tostring(numSlots) .. ", Items=" .. itemCount)
        end
    end
    
    -- Final result
    self:Print("IsWarbandBankOpen(): " .. tostring(self:IsWarbandBankOpen()))
    self:Print("======================")
end

---Force scan without checking if bank is open (for debugging)
function WarbandNexus:ForceScanWarbandBank()
    self:Print("Force scanning Warband Bank (bypassing open check)...")
    
    -- Temporarily mark bank as open for scan
    local wasOpen = self.bankIsOpen
    self.bankIsOpen = true
    
    -- Use the existing Scanner module
    local success = self:ScanWarbandBank()
    
    -- Restore original state
    self.bankIsOpen = wasOpen
    
    if success then
        self:Print("Force scan complete!")
    else
        self:Print("|cffff0000Force scan failed. Bank might not be accessible.|r")
    end
end

--[[
    Wipe all addon data and reload UI
    This is a destructive operation that cannot be undone
]]
function WarbandNexus:WipeAllData()
    self:Print("|cffff9900Wiping all addon data...|r")
    
    -- Close UI first
    if self.HideMainWindow then
        self:HideMainWindow()
    end
    
    -- Clear all caches
    if self.ClearAllCaches then
        self:ClearAllCaches()
    end
    
    -- Reset the entire database
    if self.db then
        self.db:ResetDB(true)
    end
    
    self:Print("|cff00ff00All data wiped! Reloading UI...|r")
    
    -- Reload UI after a short delay
    C_Timer.After(1, function()
        if C_UI and C_UI.Reload then
            C_UI.Reload()
        else
            ReloadUI()
        end
    end)
end

function WarbandNexus:InitializeConfig()
    -- Implemented in Config.lua
end

--[[
    Print current character's PvE data for debugging
]]
function WarbandNexus:PrintPvEData()
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    self:Print("=== PvE Data for " .. name .. " ===")
    
    local pveData = self:CollectPvEData()
    
    -- Great Vault
    self:Print("|cffffd700Great Vault:|r")
    if pveData.greatVault and #pveData.greatVault > 0 then
        for i, activity in ipairs(pveData.greatVault) do
            local typeName = "Unknown"
            local typeNum = activity.type
            
            -- Try Enum first, fallback to numbers
            if Enum and Enum.WeeklyRewardChestThresholdType then
                if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then typeName = "Raid"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then typeName = "M+"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then typeName = "PvP"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then typeName = "World"
                end
            else
                -- Fallback to numeric values
                if typeNum == 1 then typeName = "Raid"
                elseif typeNum == 2 then typeName = "M+"
                elseif typeNum == 3 then typeName = "PvP"
                elseif typeNum == 4 then typeName = "World"
                end
            end
            
            self:Print(string.format("  %s (type=%d) [%d]: %d/%d (Level %d)", 
                typeName, typeNum, activity.index or 0, 
                activity.progress or 0, activity.threshold or 0,
                activity.level or 0))
        end
    else
        self:Print("  No vault data available")
    end
    
    -- Mythic+
    self:Print("|cffa335eeM+ Keystone:|r")
    if pveData.mythicPlus and pveData.mythicPlus.keystone then
        local ks = pveData.mythicPlus.keystone
        self:Print(string.format("  %s +%d", ks.name or "Unknown", ks.level or 0))
    else
        self:Print("  No keystone")
    end
    if pveData.mythicPlus then
        if pveData.mythicPlus.weeklyBest then
            self:Print(string.format("  Weekly Best: +%d", pveData.mythicPlus.weeklyBest))
        end
        if pveData.mythicPlus.runsThisWeek then
            self:Print(string.format("  Runs This Week: %d", pveData.mythicPlus.runsThisWeek))
        end
    end
    
    -- Lockouts
    self:Print("|cff0070ddRaid Lockouts:|r")
    if pveData.lockouts and #pveData.lockouts > 0 then
        for i, lockout in ipairs(pveData.lockouts) do
            self:Print(string.format("  %s (%s): %d/%d", 
                lockout.name or "Unknown",
                lockout.difficultyName or "Normal",
                lockout.progress or 0,
                lockout.total or 0))
        end
    else
        self:Print("  No active lockouts")
    end
    
    self:Print("===========================")
    
    -- Save the data
    if self.db.global.characters and self.db.global.characters[key] then
        self.db.global.characters[key].pve = pveData
        self.db.global.characters[key].lastSeen = time()
        self:Print("|cff00ff00Data saved! Use /wn pve to view in UI|r")
    end
end

--[[============================================================================
    FAVORITE CHARACTERS MANAGEMENT
============================================================================]]

---Check if a character is favorited
---@param characterKey string Character key ("Name-Realm")
---@return boolean
function WarbandNexus:IsFavoriteCharacter(characterKey)
    if not self.db or not self.db.global or not self.db.global.favoriteCharacters then
        return false
    end
    
    for _, favKey in ipairs(self.db.global.favoriteCharacters) do
        if favKey == characterKey then
            return true
                    end
                end
    
    return false
    end
    
---Toggle favorite status for a character
---@param characterKey string Character key ("Name-Realm")
---@return boolean New favorite status
function WarbandNexus:ToggleFavoriteCharacter(characterKey)
    if not self.db or not self.db.global then
        return false
    end
    
    -- Initialize if needed
    if not self.db.global.favoriteCharacters then
        self.db.global.favoriteCharacters = {}
    end
    
    local favorites = self.db.global.favoriteCharacters
    local isFavorite = self:IsFavoriteCharacter(characterKey)
    
    if isFavorite then
        -- Remove from favorites
        for i, favKey in ipairs(favorites) do
            if favKey == characterKey then
                table.remove(favorites, i)
                self:Print("|cffffff00Removed from favorites:|r " .. characterKey)
                                break
                            end
                        end
        return false
    else
        -- Add to favorites
        table.insert(favorites, characterKey)
        self:Print("|cffffd700Added to favorites:|r " .. characterKey)
        return true
        end
    end
    
---Get all favorite characters
---@return table Array of favorite character keys
function WarbandNexus:GetFavoriteCharacters()
    if not self.db or not self.db.global or not self.db.global.favoriteCharacters then
        return {}
    end
    
    return self.db.global.favoriteCharacters
end

-- PerformItemSearch() moved to Modules/DataService.lua





--[[
    Get warband bank's total copper (calculated from gold/silver/copper breakdown)
    @param warbandData table - Warband bank data from SavedVariables
    @return number - Total copper amount
]]
function WarbandNexus:GetWarbandBankTotalCopper(warbandData)
    if not warbandData then
        warbandData = self.db and self.db.global and self.db.global.warbandBank
    end
    if not warbandData then return 0 end
    if warbandData.gold or warbandData.silver or warbandData.copper then
        local gold = warbandData.gold or 0
        local silver = warbandData.silver or 0
        local copper = warbandData.copper or 0
        return (gold * 10000) + (silver * 100) + copper
    end
    if warbandData.totalCopper then
        return warbandData.totalCopper
    end
    return 0
end
