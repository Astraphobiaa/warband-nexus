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

-- Character Inventory Bags (0-4 + Reagent Bag)
local INVENTORY_BAGS = {
    Enum.BagIndex.Backpack or 0,
    Enum.BagIndex.Bag_1 or 1,
    Enum.BagIndex.Bag_2 or 2,
    Enum.BagIndex.Bag_3 or 3,
    Enum.BagIndex.Bag_4 or 4,
}

-- Reagent Bag (TWW: Enum.BagIndex.ReagentBag or 5)
if Enum.BagIndex.ReagentBag then
    table.insert(INVENTORY_BAGS, Enum.BagIndex.ReagentBag)
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
ns.INVENTORY_BAGS = INVENTORY_BAGS
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

--[[============================================================================
    EXTRACTED FUNCTIONS - See Service Modules:
    → Modules/Utilities.lua: GetCharTotalCopper, GetWarbandBankMoney, GetWarbandBankTotalCopper, IsWarbandBag, IsWarbandBankOpen, GetBagSize, GetItemDisplayName, GetPetNameFromTooltip
    → Modules/CharacterService.lua: ConfirmCharacterTracking, IsCharacterTracked, ShowCharacterTrackingConfirmation, IsFavoriteCharacter, ToggleFavoriteCharacter, GetFavoriteCharacters
    → Modules/DebugService.lua: Debug, TestCommand, PrintCharacterList, PrintPvEData, PrintBankDebugInfo, ForceScanWarbandBank, WipeAllData
    → Modules/CommandService.lua: SlashCommand (full routing logic)
    → Modules/DataService.lua: SaveCurrentCharacterData, UpdateCharacterGold, CollectPvEData, GetAllCharacters, PerformItemSearch
    → Modules/UI.lua: RefreshUI, RefreshPvEUI, OpenOptions
    → Modules/MinimapButton.lua: InitializeDataBroker (now InitializeMinimapButton)
============================================================================]]

--[[============================================================================
    ADDON VERSION TRACKING & CACHE INVALIDATION
============================================================================]]

---Check for addon version updates and invalidate caches if needed
---This ensures users get clean data after addon updates
function WarbandNexus:CheckAddonVersion()
    -- Get current addon version from Constants
    local ADDON_VERSION = ns.Constants and ns.Constants.ADDON_VERSION or "1.1.0"
    
    -- Get saved version from DB
    local savedVersion = self.db.global.addonVersion or "0.0.0"
    
    -- Check if version changed
    if savedVersion ~= ADDON_VERSION then
        print(string.format("|cff9370DB[WN]|r New version detected: %s → %s", savedVersion, ADDON_VERSION))
        print("|cffffcc00[WN]|r Invalidating all caches for clean migration...")
        
        -- Force refresh all caches
        self:ForceRefreshAllCaches()
        
        -- Update saved version
        self.db.global.addonVersion = ADDON_VERSION
        
        print("|cff00ff00[WN]|r Cache invalidation complete! All data will refresh on next login.")
    end
end

---Force refresh all caches (central cache invalidation)
---Called on addon version updates to ensure clean data
function WarbandNexus:ForceRefreshAllCaches()
    -- Reputation Cache
    if self.ClearReputationCache then
        self:ClearReputationCache()
        print("|cff9370DB[WN]|r Cleared reputation cache")
    end
    
    -- Currency Cache
    if self.db.global.currencyCache then
        self.db.global.currencyCache = nil
        print("|cff9370DB[WN]|r Cleared currency cache")
    end
    
    -- Collection Cache
    if self.db.global.collectionCache then
        self.db.global.collectionCache = nil
        print("|cff9370DB[WN]|r Cleared collection cache")
    end
    
    -- PvE Cache (will be added in Phase 1 of optimization)
    if self.db.global.pveCache then
        self.db.global.pveCache = nil
        print("|cff9370DB[WN]|r Cleared PvE cache")
    end
    
    -- Set refresh flag
    self.db.global.needsFullRefresh = true
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
    
    -- Initialize SessionCache from SavedVariables (LibDeflate + AceSerialize)
    if self.DecompressAndLoad then
        self:DecompressAndLoad()
    end
    
    -- Check addon version and invalidate caches if version changed
    -- CRITICAL: Must run BEFORE migrations to ensure clean data
    self:CheckAddonVersion()
    
    -- Run all database migrations via MigrationService
    if ns.MigrationService then
        ns.MigrationService:RunMigrations(self.db)
    else
        self:Print("|cffff0000ERROR: MigrationService not loaded!|r")
    end
    
    -- [DEPRECATED] CollectionScanner removed - now using CollectionService
    -- CollectionService auto-initializes and loads cache from DB
    -- See: InitializationService:InitializeDataServices()
    
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
                    
                    local charKey = ns.Utilities:GetCharacterKey()
                    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
                    
                    -- New character OR existing character with no isTracked field
                    if not charData or charData.isTracked == nil then
                        -- Show confirmation popup
                        if ns.CharacterService then
                            ns.CharacterService:ShowCharacterTrackingConfirmation(WarbandNexus, charKey)
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
                    if ns.CharacterService and ns.CharacterService:IsCharacterTracked(WarbandNexus) then
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
    self:RegisterChatCommand("wntest", "TestCommand")  -- Debug/test commands
    
    -- Register PLAYER_LOGOUT event for SessionCache compression
    self:RegisterEvent("PLAYER_LOGOUT", "OnPlayerLogout")
    
    -- Initialize minimap button (LibDBIcon) via InitializationService
    if ns.InitializationService then
        ns.InitializationService:InitializeMinimapButton(self)
    end
    
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
    
    -- Clean up database (remove duplicates and deprecated storage)
    -- Delayed to ensure SavedVariables are loaded and initial save is done
    if self.CleanupDatabase then
        C_Timer.After(10, function()
            local result = self:CleanupDatabase()
            -- Only print if something was cleaned
            if result and (result.duplicates > 0 or result.invalidEntries > 0 or result.deprecatedStorage > 0) then
                print(string.format("|cff00ff00[WN]|r Database cleaned: %d duplicate(s), %d invalid(s), %d deprecated storage(s)", 
                    result.duplicates, result.invalidEntries, result.deprecatedStorage))
                print("|cff00ff00[WN]|r Changes will persist after /reload")
            end
        end)
    end
    
    -- Initialize Module Manager (event-driven module toggles)
    if self.InitializeModuleManager then
        self:InitializeModuleManager()
    end
    
    -- Register AceEvent listeners for data updates
    self:RegisterMessage("WN_BAGS_UPDATED", function()
        if self.PopulateContent and self.UI and self.UI.mainFrame and self.UI.mainFrame:IsShown() then
            self:PopulateContent()
        end
    end)
    
    -- Register PLAYER_ENTERING_WORLD event for notifications and PvE data collection
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    
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
        self:RegisterEvent(event, function(_, itemID)
            -- Only process if Plans module is enabled
            if self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.plans ~= false then
                -- INCREMENTAL UPDATE: Remove from uncollected cache (DB persisted)
                -- itemID is passed by NEW_MOUNT_ADDED (mountID), NEW_PET_ADDED (speciesID), NEW_TOY_ADDED (itemID), etc.
                if itemID and (collectionType == "mount" or collectionType == "pet" or collectionType == "toy") then
                    if self.RemoveFromUncollected then
                        self:RemoveFromUncollected(collectionType, itemID)
                        print("|cff00ff00[WN Core]|r " .. collectionType .. " collected: ID=" .. tostring(itemID))
                        
                        -- Get item info and show notification
                        C_Timer.After(0.1, function()
                            local itemName, itemIcon
                            
                            if collectionType == "mount" then
                                itemName, _, itemIcon = C_MountJournal.GetMountInfoByID(itemID)
                            elseif collectionType == "pet" then
                                itemName, itemIcon = C_PetJournal.GetPetInfoBySpeciesID(itemID)
                            elseif collectionType == "toy" then
                                local itemInfo = {GetItemInfo(itemID)}
                                itemName = itemInfo[1]
                                itemIcon = itemInfo[10]
                            end
                            
                            if itemName and self.ShowModalNotification then
                                local actionTexts = {
                                    mount = "You have collected a mount",
                                    pet = "You have collected a battle pet",
                                    toy = "You have collected a toy"
                                }
                                
                                self:ShowModalNotification({
                                    icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                    itemName = itemName,
                                    action = actionTexts[collectionType] or "You have collected",
                                    autoDismiss = 10,
                                    playSound = true,
                                    glowAtlas = "loottoast-glow-epic"
                                })
                            end
                        end)
                    end
                elseif collectionType == "achievement" and event == "ACHIEVEMENT_EARNED" then
                    -- Achievement notification (itemID is achievementID here)
                    C_Timer.After(0.1, function()
                        local _, achievementName, _, _, _, _, _, _, _, achievementIcon = GetAchievementInfo(itemID)
                        if achievementName and self.ShowModalNotification then
                            self:ShowModalNotification({
                                icon = achievementIcon or "Interface\\Icons\\Achievement_Quests_Completed_08",
                                itemName = achievementName,
                                action = "You have earned an achievement",
                                autoDismiss = 10,
                                playSound = true,
                                glowAtlas = "loottoast-glow-legendary"
                            })
                        end
                    end)
                elseif collectionType == "illusion" and event == "TRANSMOG_COLLECTION_UPDATED" then
                    -- Illusion/Transmog notification
                    -- TRANSMOG_COLLECTION_UPDATED doesn't provide specific ID, so we can't show notification
                    -- Instead, we just invalidate the cache and let the UI refresh on next load
                    print("|cff9370DB[WN Core]|r Transmog collection updated, cache will refresh on next Plans tab open")
                end
                
                -- [DEPRECATED] CollectionScanner removed - now using CollectionService
                -- CollectionService handles cache invalidation automatically via events
                -- No manual invalidation needed - event-driven updates handle this
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
    -- THROTTLED: Use bucket to prevent spam on login (0.5s delay)
    self:RegisterBucketEvent("PLAYERBANKSLOTS_CHANGED", 0.5, "OnBagUpdate") -- Personal bank slot changes
    
    -- Inventory bag events (scan when bags change)
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnInventoryBagsChanged") -- Fires when bag operations complete
    
    -- Guild Bank events (disabled by default, set ENABLE_GUILD_BANK=true to enable)
    if ENABLE_GUILD_BANK then
        self:RegisterEvent("GUILDBANKFRAME_OPENED", "OnGuildBankOpened")
        self:RegisterEvent("GUILDBANKFRAME_CLOSED", "OnGuildBankClosed")
        self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", "OnBagUpdate") -- Guild bank slot changes
    end
    
    self:RegisterEvent("PLAYER_MONEY", "OnMoneyChanged")
    self:RegisterEvent("ACCOUNT_MONEY", "OnMoneyChanged") -- Warband Bank gold changes
    
    -- Currency events (throttled handling in EventManager)
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "OnCurrencyChanged")
    
    -- M+ completion events (for cache updates)
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED")  -- Fires when M+ run completes
    self:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD")  -- Fires when new best time
    
    -- Combat protection for UI (taint prevention)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart") -- Entering combat
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")  -- Leaving combat
    
    -- PvE events managed by EventManager (throttled)
    
    -- Collection tracking events are now managed by EventManager (debounced versions)
    -- See Modules/EventManager.lua InitializeEventManager()
    
    -- Register bucket events for bag updates (fast refresh for responsive UI)
    self:RegisterBucketEvent("BAG_UPDATE", 0.15, "OnBagUpdate")
    
    -- Container hooks managed via BAG_UPDATE_DELAYED event (TWW 11.0+ compatible)
    
    -- Register event listeners for UI refresh
    self:RegisterMessage("WN_BAGS_UPDATED", function()
        -- Refresh UI when bags are updated (personal items)
        if self.RefreshUI and self.UI and self.UI.mainFrame and self.UI.mainFrame:IsShown() then
            self:RefreshUI()
        end
    end)
    
    -- Initialize all modules via InitializationService
    -- This manages module startup sequence, timing, and dependencies
    if ns.InitializationService then
        ns.InitializationService:InitializeAllModules(self)
    else
        self:Print("|cffff0000ERROR: InitializationService not loaded!|r")
    end
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
--[[============================================================================
    DELEGATE FUNCTIONS - Service Calls
    These wrappers maintain API compatibility while delegating to services
============================================================================]]

function WarbandNexus:SlashCommand(input)
    ns.CommandService:HandleSlashCommand(self, input)
end

function WarbandNexus:TestCommand(input)
    ns.DebugService:TestCommand(self, input)
end

function WarbandNexus:PrintCharacterList()
    ns.DebugService:PrintCharacterList(self)
end

function WarbandNexus:PrintPvEData()
    ns.DebugService:PrintPvEData(self)
end

function WarbandNexus:Debug(message)
    ns.DebugService:Debug(self, message)
end

function WarbandNexus:PrintBankDebugInfo()
    ns.DebugService:PrintBankDebugInfo(self)
end

function WarbandNexus:ForceScanWarbandBank()
    ns.DebugService:ForceScanWarbandBank(self)
end

function WarbandNexus:WipeAllData()
    ns.DebugService:WipeAllData(self)
end

function WarbandNexus:GetItemDisplayName(itemID, itemName, classID)
    return ns.Utilities:GetItemDisplayName(itemID, itemName, classID)
end

function WarbandNexus:GetPetNameFromTooltip(itemID)
    return ns.Utilities:GetPetNameFromTooltip(itemID)
end

--[[============================================================================
    EVENT HANDLERS
============================================================================]]

--[[
    [DEPRECATED] OnBankOpened duplicate removed (lines 678-709)
    The complete implementation with proper warband bank handling is at line 1178.
    This duplicate has been removed to prevent conflicts and ensure consistent behavior.
]]

--[[ COMMENTED OUT OLD CODE - MOVED TO SERVICES
    
    -- Help command - show available commands
    if cmd == "help" then
        self:Print("|cff00ccffWarband Nexus|r - Available commands:")
        self:Print("  |cff00ccff/wn|r - Open addon window")
        self:Print("  |cff00ccff/wn options|r - Open settings")
        self:Print("  |cff00ccff/wn debug|r - Toggle debug mode")
        self:Print("  |cff00ccff/wn scanquests [tww|df|sl]|r - Scan & debug daily quests")
        self:Print("  |cff00ccff/wntest overflow|r - Check font overflow")
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
        
        local playerKey = ns.Utilities:GetCharacterKey()
        
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
        -- Phase 3: CacheManager removed - Show cache service stats instead
        self:Print("|cff9370DB[Cache Services Status]|r")
        self:Print("Reputation Cache: " .. (self.db.global.reputationCache and "Loaded" or "Empty"))
        self:Print("Currency Cache: " .. (self.db.global.currencyCache and "Loaded" or "Empty"))
        
        -- Collection cache with item counts
        if self.db.global.collectionCache and self.db.global.collectionCache.uncollected then
            local cache = self.db.global.collectionCache.uncollected
            local achievementCount = 0
            for _ in pairs(cache.achievement or {}) do achievementCount = achievementCount + 1 end
            self:Print(string.format("Collection Cache: Loaded (%d achievements)", achievementCount))
        else
            self:Print("Collection Cache: Empty")
        end
        
        self:Print("PvE Cache: " .. (self.db.global.pveCache and "Loaded" or "Empty"))
        self:Print("Items Cache: Per-character, use /wn chars to see data")
        
    elseif cmd == "scanachieves" or cmd == "scanachievements" then
        self:Print("|cffffcc00Manually triggering achievement scan...|r")
        if self.ScanAchievementsAsync then
            -- Reset loading state
            if ns.CollectionLoadingState then
                ns.CollectionLoadingState.isLoading = false
                ns.CollectionLoadingState.loadingProgress = 0
            end
            -- Force scan (bypass cooldown)
            local collectionService = ns.CollectionService or {}
            local collectionCache = collectionService.cache or {}
            if collectionCache.lastScan then
                collectionCache.lastScan = 0  -- Force scan
            end
            self:ScanAchievementsAsync()
            self:Print("|cff00ff00Achievement scan started! Check Plans > Achievements tab.|r")
        else
            self:Print("|cffff0000ERROR: ScanAchievementsAsync not found!|r")
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
        -- Parse: /wn testloot [type] [id]
        local typeArg, idArg = input:match("^testloot%s+(%w+)%s*(%d*)") -- Extract type and optional id
        if self.TestLootNotification then
            self:TestLootNotification(typeArg, idArg ~= "" and tonumber(idArg) or nil)
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
        -- Parse: /wn testevents [type] [id]
        local typeArg, idArg = input:match("^testevents%s+(%w+)%s*(%d*)") -- Extract type and optional id
        if self.TestNotificationEvents then
            self:TestNotificationEvents(typeArg, idArg ~= "" and tonumber(idArg) or nil)
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
]]

--[[============================================================================
    EVENT HANDLERS (Continued - Bank Events)
============================================================================]]

function WarbandNexus:OnBankOpened()
    self.bankIsOpen = true
    
    -- Scan personal bank
    if self.db.profile.autoScan and self.ScanPersonalBank then
        self:ScanPersonalBank()
    end
    
    -- Scan character inventory bags
    if self.db.profile.autoScan and self.ScanCharacterBags then
        self:Debug("[BANK_OPENED] Triggering character bag scan")
        self:ScanCharacterBags()
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

---Generate bag fingerprint for change detection
---Returns totalSlots, usedSlots, fingerprint (hash of all item IDs + counts)
function WarbandNexus:GetBagFingerprint()
    local totalSlots = 0
    local usedSlots = 0
    local fingerprint = ""
    
    -- Scan inventory bags (0-4)
    for bagID = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
        totalSlots = totalSlots + numSlots
        
        for slotIndex = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slotIndex)
            if itemInfo then
                usedSlots = usedSlots + 1
                local itemID = itemInfo.itemID or 0
                local count = itemInfo.stackCount or 1
                -- Build fingerprint: concatenate itemID:count pairs
                fingerprint = fingerprint .. itemID .. ":" .. count .. ","
            end
        end
    end
    
    return totalSlots, usedSlots, fingerprint
end

--[[
    Handler for inventory bag changes (BAG_UPDATE_DELAYED)
    Scans character bags when bag operations complete
    Optimized for bulk operations (loot, mail, vendor)
]]
function WarbandNexus:OnInventoryBagsChanged()
    -- Only scan if module enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.items then
        return
    end
    
    -- Only auto-scan if enabled
    if not self.db.profile.autoScan then
        return
    end
    
    -- OPTIMIZATION: Check if bags actually changed (fingerprint comparison)
    local totalSlots, usedSlots, newFingerprint = self:GetBagFingerprint()
    
    -- Initialize last snapshot if not exists
    if not self.lastBagSnapshot then
        self.lastBagSnapshot = { fingerprint = "", totalSlots = 0, usedSlots = 0 }
    end
    
    -- Compare fingerprints (cheap operation)
    if newFingerprint == self.lastBagSnapshot.fingerprint then
        -- No actual change detected, skip scan
        return
    end
    
    -- Update snapshot
    self.lastBagSnapshot.fingerprint = newFingerprint
    self.lastBagSnapshot.totalSlots = totalSlots
    self.lastBagSnapshot.usedSlots = usedSlots
    
    -- DEBOUNCE: Cancel pending timer and schedule new one
    -- Use 1 second delay for bulk operations (mail, loot all, vendor)
    if self.pendingBagsScanTimer then
        self:CancelTimer(self.pendingBagsScanTimer)
    end
    
    self.pendingBagsScanTimer = self:ScheduleTimer(function()
        if self.ScanCharacterBags then
            self:ScanCharacterBags()
        end
        self.pendingBagsScanTimer = nil
    end, 1.0) -- 1 second debounce for bulk operations
end

--[[============================================================================
    GUILD BANK HANDLERS
============================================================================]]
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
-- Delegates to DataService and fires event for UI updates
function WarbandNexus:OnMoneyChanged()
    self.db.char.lastKnownGold = GetMoney()
    
    -- Update character gold via DataService
    if self.UpdateCharacterGold then
        self:UpdateCharacterGold()
    end
    
    print("|cff9370DB[WN Core]|r Money changed - firing update event")
    
    -- Fire event for UI refresh (instead of direct RefreshUI call)
    -- Use very short delay to batch multiple money events
    if not self.moneyRefreshPending then
        self.moneyRefreshPending = true
        C_Timer.After(0.05, function()
            if WarbandNexus then
                WarbandNexus.moneyRefreshPending = false
                WarbandNexus:SendMessage("WN_MONEY_UPDATED")
            end
        end)
    end
end

--[[
    Called when currency changes
    Delegates to DataService and fires event for UI updates
]]
function WarbandNexus:OnCurrencyChanged()
    -- Check if module is enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.currencies then
        return
    end
    
    -- Update currency data via DataService
    if self.UpdateCurrencyData then
        self:UpdateCurrencyData()
    end
    
    print("|cff9370DB[WN Core]|r Currency changed - firing update event")
    
    -- Fire event for UI refresh (instead of direct RefreshUI call)
    -- Use short delay to batch multiple currency events
    if not self.currencyRefreshPending then
        self.currencyRefreshPending = true
        C_Timer.After(0.1, function()
            if WarbandNexus then
                WarbandNexus.currencyRefreshPending = false
                WarbandNexus:SendMessage("WN_CURRENCY_UPDATED")
            end
        end)
    end
end

--[[
    [DEPRECATED] Called when reputation changes
    NOTE: This function is NO LONGER USED!
    Reputation events are now handled by EventManager's OnReputationChangedThrottled
    Keeping this function for backwards compatibility only
]]
function WarbandNexus:OnReputationChanged()
    -- Deprecated - reputation handling moved to EventManager for throttling
    -- All reputation events now go through EventManager:OnReputationChangedThrottled
    self:Debug("WARNING: OnReputationChanged called - this is deprecated, check event registration")
end

--[[
    Called when M+ dungeon run completes
    Delegates to DataService and fires event for UI updates
]]
function WarbandNexus:CHALLENGE_MODE_COMPLETED(mapChallengeModeID, level, time, onTime, keystoneUpgradeLevels)
    local charKey = ns.Utilities:GetCharacterKey()
    print("|cff9370DB[WN Core]|r M+ completed (Map: " .. tostring(mapChallengeModeID) .. ", Level: " .. tostring(level) .. ") - updating PvE data")
    
    -- Re-collect PvE data via DataService
    if self.CollectPvEData then
        local pveData = self:CollectPvEData()
        
        -- Update via DataService
        if self.UpdatePvEDataV2 and self.db.global.characters and self.db.global.characters[charKey] then
            self:UpdatePvEDataV2(charKey, pveData)
        end
        
        -- Fire event for UI refresh (instead of direct call)
        self:SendMessage("WN_PVE_UPDATED", charKey)
    end
end

--[[
    Called when new weekly M+ record is set
    Delegates to PvE data update
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
        if ns.CharacterService and ns.CharacterService:IsCharacterTracked(self) then
            -- AUTOMATIC: Start PvE data collection with staggered approach (performance optimized)
            -- Stages: 3s (Vault), 5s (M+), 7s (Lockouts) - spreads load to prevent FPS drops
            if self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.pve then
                local charKey = ns.Utilities:GetCharacterKey()
                if self.CollectPvEDataStaggered then
                    -- Staggered collection starts at 3s, completes by 7s
                    self:CollectPvEDataStaggered(charKey)
                end
            end
        end
    end
    
    -- Scan character inventory bags on login (after 1 second)
    C_Timer.After(1, function()
        if WarbandNexus and WarbandNexus.ScanCharacterBags then
            WarbandNexus:Debug("[LOGIN] Triggering character bag scan")
            WarbandNexus:ScanCharacterBags()
        end
    end)
    
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
    
    -- Process queued bag updates after combat
    if self.pendingBagUpdateAfterCombat then
        C_Timer.After(0.5, function()  -- Delay slightly to avoid immediate post-combat spam
            if not InCombatLockdown() and self.pendingBagUpdateAfterCombat then
                self:OnBagUpdate(self.pendingBagUpdateAfterCombat)
                self.pendingBagUpdateAfterCombat = nil
            end
        end)
    end
end

--[[
    Called when PvE data changes (Great Vault, Lockouts, M+ completion)
    Delegates to DataService for business logic
]]
function WarbandNexus:OnPvEDataChanged()
    local charKey = ns.Utilities:GetCharacterKey()
    
    if not self.db.global.characters or not self.db.global.characters[charKey] then
        return
    end
    
    print("|cff9370DB[WN Core]|r PvE data changed event - delegating to DataService")
    
    -- Collect updated PvE data via DataService
    if self.CollectPvEData then
        local pveData = self:CollectPvEData()
        
        -- Update database via DataService
        if self.UpdatePvEDataV2 then
            self:UpdatePvEDataV2(charKey, pveData)
        end
        
        -- Invalidate cache to trigger UI refresh
        if self.InvalidatePvECache then
            self:InvalidatePvECache(charKey)
        end
    end
end

--[[
    Called when keystone might have changed (delayed bag update)
    Delegates to DataService for business logic
]]
function WarbandNexus:OnKeystoneChanged()
    -- Throttle keystone checks to avoid spam
    if self.keystoneCheckPending then
        return
    end
    
    self.keystoneCheckPending = true
    C_Timer.After(0.5, function()
        if not WarbandNexus then return end
        WarbandNexus.keystoneCheckPending = false
        
        local charKey = ns.Utilities:GetCharacterKey()
        
        -- Scan and update keystone data (lightweight check)
        if WarbandNexus.ScanMythicKeystone then
            local keystoneData = WarbandNexus:ScanMythicKeystone()
            
            if WarbandNexus.db and WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey] then
                local oldKeystone = WarbandNexus.db.global.characters[charKey].mythicKey
                
                -- Only update if keystone actually changed
                local keystoneChanged = false
                if not oldKeystone and keystoneData then
                    keystoneChanged = true
                    print("|cff00ff00[WN Core]|r New keystone detected: +" .. keystoneData.level .. " " .. (keystoneData.mapName or "Unknown"))
                elseif oldKeystone and keystoneData then
                    keystoneChanged = (oldKeystone.level ~= keystoneData.level or 
                                     oldKeystone.mapID ~= keystoneData.mapID)
                    if keystoneChanged then
                        print("|cffffff00[WN Core]|r Keystone changed: " .. oldKeystone.level .. " → " .. keystoneData.level)
                    end
                elseif oldKeystone and not keystoneData then
                    keystoneChanged = true
                    print("|cffff4444[WN Core]|r Keystone removed/used")
                end
                
                if keystoneChanged then
                    WarbandNexus.db.global.characters[charKey].mythicKey = keystoneData
                    WarbandNexus.db.global.characters[charKey].lastSeen = time()
                    print("|cff00ff00[WN Core]|r Keystone data updated for " .. charKey)
                    
                    -- Fire event for UI update (only PvE tab needs refresh)
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage("WARBAND_PVE_UPDATED")
                    end
                    
                    -- Invalidate cache to refresh UI
                    if WarbandNexus.InvalidateCharacterCache then
                        WarbandNexus:InvalidateCharacterCache()
                    end
                else
                    print("|cff9370DB[WN Core]|r Keystone unchanged, skipping update")
                end
            end
        end
    end)
end

--[[
    Event handler for collection changes (mounts, pets, toys)
    Delegates to CollectionService and cache invalidation
]]
function WarbandNexus:OnCollectionChanged(event)
    -- Minimal throttle only for TOYS_UPDATED (can fire frequently)
    local needsThrottle = (event == "TOYS_UPDATED")
    
    if needsThrottle and self.collectionCheckPending then
        return
    end
    
    if needsThrottle then
        self.collectionCheckPending = true
        C_Timer.After(0.2, function()
            if WarbandNexus then
                WarbandNexus.collectionCheckPending = false
            end
        end)
    end
    
    local charKey = ns.Utilities:GetCharacterKey()
    print("|cff9370DB[WN Core]|r Collection changed event (" .. event .. ") - invalidating cache")
    
    if self.db.global.characters and self.db.global.characters[charKey] then
        -- Update timestamp
        self.db.global.characters[charKey].lastSeen = time()
        
        -- Invalidate collection cache (data changed)
        if self.InvalidateCollectionCache then
            self:InvalidateCollectionCache()
        end
        
        -- Fire event for UI to refresh (instead of direct RefreshUI call)
        self:SendMessage("WN_COLLECTION_UPDATED", charKey)
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
        
        local charKey = ns.Utilities:GetCharacterKey()
        print("|cff9370DB[WN Core]|r Pet list changed - invalidating cache")
        
        if WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey] then
            WarbandNexus.db.global.characters[charKey].lastSeen = time()
            
            -- Invalidate collection cache
            if WarbandNexus.InvalidateCollectionCache then
                WarbandNexus:InvalidateCollectionCache()
            end
            
            -- Fire event for UI refresh (instead of direct call)
            WarbandNexus:SendMessage("WN_COLLECTION_UPDATED", charKey)
        end
    end)
end

--[[============================================================================
    BAG UPDATE HANDLER (Incremental Scanning)
============================================================================]]

---@param bagIDs table|string Table of bag IDs that were updated, or event name for legacy events
function WarbandNexus:OnBagUpdate(bagIDs)
    -- Check if module is enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.items then
        return
    end
    
    -- Handle legacy event calls (PLAYERBANKSLOTS_CHANGED passes event name as string)
    -- NOTE: This is throttled via RegisterBucketEvent (0.5s) to prevent spam on login
    if type(bagIDs) ~= "table" then
        -- For legacy events, just rescan everything (bank must be open)
        if self.bankIsOpen and self.ScanPersonalBank then
            self:ScanPersonalBank()
        end
        if self.warbandBankIsOpen and self.ScanWarbandBank then
            self:ScanWarbandBank()
        end
        if self.ScanCharacterBags then
            self:ScanCharacterBags()
        end
        return
    end
    
    -- Debug: Show which bags were updated
    local bagIDList = {}
    for bagID in pairs(bagIDs) do
        table.insert(bagIDList, tostring(bagID))
    end
    self:Debug("[BAG_UPDATE] Bags changed: " .. table.concat(bagIDList, ", "))
    
    -- INCREMENTAL SCANNING: Collect which specific bags changed
    local warbandBagsChanged = {}
    local personalBagsChanged = {}
    
    for bagID in pairs(bagIDs) do
        -- Check Warband bags
        if ns.Utilities:IsWarbandBag(bagID) then
            table.insert(warbandBagsChanged, bagID)
        end
        -- Check Personal bank bags (including main bank -1 and bags 6-12)
        if bagID == -1 or (bagID >= 6 and bagID <= 12) then
            table.insert(personalBagsChanged, bagID)
        end
        -- NOTE: Inventory bags (0-5) are handled by BAG_UPDATE_DELAYED
    end
    
    -- Bank bags require bank to be open
    local hasChanges = (#warbandBagsChanged > 0 or #personalBagsChanged > 0) and self.bankIsOpen
    
    if not hasChanges then
        return
    end
    
    -- Batch updates with a timer to avoid spam (only for bank bags)
    if self.pendingScanTimer then
        self:CancelTimer(self.pendingScanTimer)
    end
    
    self.pendingScanTimer = self:ScheduleTimer(function()
        -- INCREMENTAL SCAN: Only scan changed bags
        if #warbandBagsChanged > 0 and self.warbandBankIsOpen and self.ScanWarbandBank then
            self:ScanWarbandBank(warbandBagsChanged)
        end
        if #personalBagsChanged > 0 and self.bankIsOpen and self.ScanPersonalBank then
            self:ScanPersonalBank(personalBagsChanged)
            
            -- CRITICAL: Also scan bags when bank changes (items moved between bank/bags)
            -- Full scan needed since we don't know which inventory bag was affected
            if self.ScanCharacterBags then
                self:ScanCharacterBags() -- Full scan (nil = all bags)
            end
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

--[[
    Utility Functions
]]

--[[============================================================================
    NOTE: Additional delegate functions and utility wrappers are defined at the
    top of this file under "DELEGATE FUNCTIONS - Service Calls" section.
    
    Stub implementations are in their respective service modules:
    - ScanWarbandBank() → Modules/DataService.lua
    - ToggleMainWindow() → Modules/UI.lua
    - OpenDepositQueue() → Modules/Banker.lua
    - SearchItems() → Modules/UI.lua
============================================================================]]
