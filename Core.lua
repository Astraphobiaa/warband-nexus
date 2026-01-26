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
        
        -- Behavior settings
        autoScan = true,           -- Auto-scan when bank opens
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
        
        -- Font Management (Resolution-aware scaling)
        fonts = {
            fontFace = "Fonts\\FRIZQT__.TTF",  -- Default: Friz Quadrata
            scalePreset = "normal",            -- Preset: tiny/small/normal/large/xlarge
            scaleCustom = 1.0,                 -- Custom scale multiplier
            useCustomScale = false,            -- Use custom scale instead of preset
            antiAliasing = "OUTLINE",          -- AA flags: none/OUTLINE/THICKOUTLINE
            usePixelNormalization = true,      -- Enable resolution-aware scaling
            baseSizes = {
                header = 16,    -- Section headers, tab labels
                title = 14,     -- Card titles, character names
                subtitle = 12,  -- Type badges, progress labels
                body = 12,      -- Description text, source info
                small = 10,     -- Requirements, tooltips, fine print
            },
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
    
    -- CRITICAL: Export db to namespace for FontManager and other modules
    ns.db = self.db
    
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
        
        -- ONE-TIME: Add isTracked field to existing characters (default: true for backward compatibility)
        if not self.db.global.trackingMigrationV1 then
            local updated = 0
            for charKey, charData in pairs(self.db.global.characters) do
                if charData and charData.isTracked == nil then
                    -- Existing characters automatically tracked (backward compatibility)
                    charData.isTracked = true
                    updated = updated + 1
                end
            end
            if updated > 0 then
                self:Debug("Tracking migration: Marked " .. updated .. " existing characters as tracked")
            end
            self.db.global.trackingMigrationV1 = true
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
            -- ONLY on initial login (not reload)
            if isInitialLogin then
                -- Check if character needs tracking confirmation (0.5s delay to ensure DB is loaded)
                C_Timer.After(0.5, function()
                    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
                        return
                    end
                    
                    local charKey = UnitName("player") .. "-" .. GetRealmName()
                    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
                    
                    -- New character OR existing character with no isTracked field
                    if not charData or charData.isTracked == nil then
                        -- Show confirmation popup
                        if WarbandNexus.ShowCharacterTrackingConfirmation then
                            WarbandNexus:ShowCharacterTrackingConfirmation(charKey)
                        end
                        return  -- Don't trigger SaveCharacter or notifications yet
                    end
                    
                    -- Character has tracking status - proceed with normal save
                    C_Timer.After(1.5, function()
                        if WarbandNexus and WarbandNexus.SaveCharacter then
                            WarbandNexus:SaveCharacter()
                        end
                    end)
                    
                    -- Trigger notifications (only for tracked characters)
                    if WarbandNexus.IsCharacterTracked and WarbandNexus:IsCharacterTracked() then
                        C_Timer.After(2, function()
                            if WarbandNexus and WarbandNexus.CheckNotificationsOnLogin then
                                WarbandNexus:CheckNotificationsOnLogin()
                            end
                        end)
                    end
                end)
            else
                -- Reload UI: Always save character (no popup)
                C_Timer.After(2, function()
                    if WarbandNexus and WarbandNexus.SaveCharacter then
                        WarbandNexus:SaveCharacter()
                    end
                end)
            end
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
    -- FontManager is now loaded via .toc (no loadfile needed - it's forbidden in WoW)
    
    -- Refresh colors from database on enable
    if ns.UI_RefreshColors then
        ns.UI_RefreshColors()
    end
    
    -- Register PLAYER_ENTERING_WORLD event for notifications and PvE data collection
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    
    -- Initialize CollectionScanner with delay (background scan after login)
    -- Delay prevents freeze during initial addon load
    C_Timer.After(2, function()
        -- Only initialize CollectionScanner if Plans module is enabled
        if self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.plans ~= false then
            if self.CollectionScanner and self.CollectionScanner.Initialize then
                self.CollectionScanner:Initialize()
            end
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
            -- Only process if Plans module is enabled
            if self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.plans ~= false then
                if self.CollectionScanner and self.CollectionScanner.InvalidateCache then
                    self.CollectionScanner:InvalidateCache(collectionType)
                end
            end
        end)
    end
    
    -- CRITICAL: Check for addon conflicts immediately on enable (only if bank module enabled)
    -- This runs on both initial login AND /reload
    -- Detect if user re-enabled conflicting addons/modules
    
    -- Session flag to prevent duplicate saves
    self.characterSaved = false
    
    -- Register events
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
    
    -- Tooltip Service: Initialize central tooltip system
    if self.Tooltip and self.Tooltip.Initialize then
        C_Timer.After(0.3, function()
            if WarbandNexus and WarbandNexus.Tooltip then
                WarbandNexus.Tooltip:Initialize()
            end
        end)
    end
    
    -- Request M+ and Weekly Rewards data immediately for instant updates
    C_Timer.After(1, function()
        if C_MythicPlus then
            C_MythicPlus.RequestMapInfo()
            C_MythicPlus.RequestRewards()
            C_MythicPlus.RequestCurrentAffixes()
        end
        if C_WeeklyRewards then
            C_WeeklyRewards.OnUIInteract()
        end
    end)
    
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

    -- Notification System: Initialize event listeners first (must be before collection tracking)
    C_Timer.After(0.5, function()
        if WarbandNexus and WarbandNexus.InitializeLootNotifications then
            WarbandNexus:InitializeLootNotifications()
        else
            WarbandNexus:Print("|cffff0000ERROR: InitializeLootNotifications not found!|r")
        end
    end)
    
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
    Refresh theme colors in real-time
]]
function WarbandNexus:RefreshTheme()
    -- Refresh colors (handled by SharedWidgets.RefreshColors)
    if ns.UI_RefreshColors then
        ns.UI_RefreshColors()
    end
    
    -- Refresh settings window if open
    local settingsFrame = _G["WarbandNexusSettingsFrame"]
    if settingsFrame and settingsFrame:IsShown() then
        -- Close and reopen to apply new colors
        settingsFrame:Hide()
        C_Timer.After(0.1, function()
            if ns.ShowSettings then
                ns.ShowSettings()
            end
        end)
    end
end

--[[============================================================================
    CHARACTER TRACKING SYSTEM (HYBRID: EVENT-DRIVEN + GUARD-BASED)
============================================================================]]

---Confirm character tracking status and broadcast event
---@param charKey string Character key (Name-Realm)
---@param isTracked boolean true = tracked (full API), false = untracked (read-only)
function WarbandNexus:ConfirmCharacterTracking(charKey, isTracked)
    if not self.db or not self.db.global then return end
    
    -- Initialize character entry if it doesn't exist
    if not self.db.global.characters then
        self.db.global.characters = {}
    end
    
    if not self.db.global.characters[charKey] then
        self.db.global.characters[charKey] = {}
    end
    
    -- Set tracking status
    self.db.global.characters[charKey].isTracked = isTracked
    self.db.global.characters[charKey].lastSeen = time()
    
    -- HYBRID: Broadcast event for modules to react (event-driven component)
    self:SendMessage("WN_CHARACTER_TRACKING_CHANGED", {
        charKey = charKey,
        isTracked = isTracked
    })
    
    if isTracked then
        self:Print("|cff00ff00Character tracking enabled.|r Data collection will begin.")
        -- Trigger initial save
        C_Timer.After(1, function()
            if self.SaveCharacter then
                self:SaveCharacter()
            end
        end)
        -- Show reload popup (systems need to reinitialize)
        C_Timer.After(1.5, function()
            if self.ShowReloadPopup then
                self:ShowReloadPopup()
            end
        end)
    else
        self:Print("|cffff8800Character tracking disabled.|r Running in read-only mode.")
    end
end

---Check if current character is tracked
---@return boolean true if tracked, false if untracked or not found
function WarbandNexus:IsCharacterTracked()
    local charKey = UnitName("player") .. "-" .. GetRealmName()
    
    if not self.db or not self.db.global or not self.db.global.characters then
        return false
    end
    
    local charData = self.db.global.characters[charKey]
    
    -- Default to false for new characters (require explicit opt-in)
    if not charData then
        return false
    end
    
    -- Default to true for backward compatibility (existing characters)
    return charData.isTracked ~= false
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
        self:Print("  |cff888888/wn testevents [type]|r - Test event system (collectible/plan/vault/quest)")
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
        
        self:Print(string.format("|cff00ff00Results: %d daily, %d world, %d weekly, %d assignments|r",
            #quests.dailyQuests, #quests.worldQuests, #quests.weeklyQuests,
            #quests.assignments or 0))
        
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
    
    elseif cmd == "testevents" then
        -- Test event-driven notification system
        local typeArg = input:match("^testevents%s+(%w+)") -- Extract word after "testevents "
        if self.TestNotificationEvents then
            self:TestNotificationEvents(typeArg)
        else
            self:Print("|cffff0000TestNotificationEvents function not found!|r")
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

--[[
    Get Warband Bank Money
    Simple wrapper for C_Bank.FetchDepositedMoney (read-only)
]]
function WarbandNexus:GetWarbandBankMoney()
    -- TWW (11.0+) API for getting warband bank gold
    if C_Bank and C_Bank.FetchDepositedMoney then
        local accountMoney = C_Bank.FetchDepositedMoney(Enum.BankType.Account)
        return accountMoney or 0
    end
    return 0
end

function WarbandNexus:OnBankOpened()
    self.bankIsOpen = true
    
    -- Scan personal bank
    if self.db.profile.autoScan and self.ScanPersonalBank then
        self:ScanPersonalBank()
    end
    
    -- Scan warband bank (delayed to ensure slots are available)
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
    end)
end

function WarbandNexus:OnBankClosed()
    self.bankIsOpen = false
    self.warbandBankIsOpen = false
end

-- All conflict detection functions removed (read-only mode)
-- Addon works with any bank addon without conflicts

---Show character tracking confirmation popup
---@param charKey string Character key (Name-Realm)
function WarbandNexus:ShowCharacterTrackingConfirmation(charKey)
    -- Create popup dialog
    StaticPopupDialogs["WARBANDNEXUS_ADD_CHARACTER"] = {
        text = "|cff00ccffWarband Nexus|r\n\nDo you want to track this character?\n\n|cffffffffTracked:|r Data collection, API calls, notifications\n|cffffffffUntracked:|r Read-only mode, no data updates",
        button1 = "Yes, Track This Character",
        button2 = "No, Read-Only Mode",
        OnAccept = function(self)
            local charKey = self.data
            if WarbandNexus and WarbandNexus.ConfirmCharacterTracking then
                WarbandNexus:ConfirmCharacterTracking(charKey, true)
            end
        end,
        OnCancel = function(self)
            local charKey = self.data
            if WarbandNexus and WarbandNexus.ConfirmCharacterTracking then
                WarbandNexus:ConfirmCharacterTracking(charKey, false)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,  -- Force user to make a choice
        exclusive = true,
        preferredIndex = 3,
    }
    
    local dialog = StaticPopup_Show("WARBANDNEXUS_ADD_CHARACTER")
    if dialog then
        dialog.data = charKey
    end
end

-- All BankFrame manipulation functions removed (read-only mode)
-- Addon no longer touches BankFrame, BankPanel, or GuildBankFrame

function WarbandNexus:OnBankClosed()
    self.bankIsOpen = false
    self.warbandBankIsOpen = false
end

-- Guild Bank Opened Handler
function WarbandNexus:OnGuildBankOpened()
    self.guildBankIsOpen = true
    
    -- Scan guild bank
    if self.db.profile.autoScan and self.ScanGuildBank then
        C_Timer.After(0.3, function()
            if WarbandNexus and WarbandNexus.ScanGuildBank then
                WarbandNexus:ScanGuildBank()
            end
        end)
    end
end

-- Guild Bank Closed Handler
function WarbandNexus:OnGuildBankClosed()
    self.guildBankIsOpen = false
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
    -- Check if module is enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.currencies then
        return
    end
    
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
    -- Check if module is enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.reputations then
        return
    end
    
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

--[[
    Called when player enters the world (login or reload)
]]
function WarbandNexus:OnPlayerEnteringWorld(event, isInitialLogin, isReloadingUi)
    -- Run on BOTH initial login AND reload (for testing)
    if isInitialLogin or isReloadingUi then
        -- GUARD: Only collect PvE data if character is tracked
        if self:IsCharacterTracked() then
            -- AUTOMATIC: Start PvE data collection with staggered approach (performance optimized)
            -- Stages: 3s (Vault), 5s (M+), 7s (Lockouts) - spreads load to prevent FPS drops
            if self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.pve then
                local charKey = UnitName("player") .. "-" .. GetRealmName()
                if self.CollectPvEDataStaggered then
                    -- Staggered collection starts at 3s, completes by 7s
                    self:CollectPvEDataStaggered(charKey)
                end
            end
        end
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
    -- Check if module is enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.items then
        return
    end
    
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
            self.warbandBankIsOpen = true
            self.bankIsOpen = true
            return true
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

--[[
    Refresh UI after font/scale changes
    Closes and reopens main window to apply new settings
]]
function WarbandNexus:RefreshUI()
    if self.mainFrame and self.mainFrame:IsShown() then
        -- Hide parent before recreation (prevent flickering)
        self.mainFrame:Hide()
        
        -- Close and recreate
        self:ToggleMainWindow()  -- Close (cleanup)
        
        C_Timer.After(0.05, function()  -- Small delay for cleanup
            self:ToggleMainWindow()  -- Reopen (recreates all UI)
            -- mainFrame:Show() is called automatically by ToggleMainWindow
        end)
    end
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
    -- Show custom settings UI (renders AceConfig with themed widgets)
    if self.ShowSettings then
        self:ShowSettings()
    elseif ns.ShowSettings then
        ns.ShowSettings()
    else
        -- Fallback to Blizzard settings panel
        Settings.OpenToCategory(ADDON_NAME)
    end
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
