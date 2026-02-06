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
        autoSaveChanges = true,    -- Live sync (real-time cache updates)
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
        
        -- Personal Bank Bag filtering (true = ignored)
        ignoredPersonalBankBags = {},  -- {[bagID] = true/false}
        
        -- Inventory Bag filtering (true = ignored)
        ignoredInventoryBags = {},  -- {[bagID] = true/false}
        
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
            showReputationGains = true,        -- Show reputation gain chat messages
            showCurrencyGains = true,          -- Show currency gain chat messages
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

-- MOVED: CheckAddonVersion() → MigrationService.lua
-- MOVED: ForceRefreshAllCaches() → DatabaseOptimizer.lua

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
    if ns.MigrationService then
        ns.MigrationService:CheckAddonVersion(self.db, self)
    end
    
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
                -- NOTE: Character tracking confirmation popup is handled by InitializationService
                -- This handler only manages SaveCharacter and notifications
                C_Timer.After(2, function()
                    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
                        return
                    end
                    
                    -- SaveCharacter will be called automatically by:
                    -- 1. InitializationService after tracking confirmation
                    -- 2. CharacterService:EnableTracking if user confirms tracking
                    -- 3. This handler as fallback for already-tracked characters
                    
                    -- Check if character is tracked and confirmation is done
                    if ns.CharacterService and ns.CharacterService:IsCharacterTracked(WarbandNexus) then
                        local charKey = ns.Utilities:GetCharacterKey()
                        local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
                        
                        -- Only save if trackingConfirmed (popup already handled by InitializationService)
                        if charData and charData.trackingConfirmed then
                            if WarbandNexus.SaveCharacter then
                                WarbandNexus:SaveCharacter()
                            end
                            
                            -- Trigger notifications (only for tracked characters)
                            C_Timer.After(0.5, function()
                                if WarbandNexus and WarbandNexus.CheckNotificationsOnLogin then
                                    WarbandNexus:CheckNotificationsOnLogin()
                                end
                            end)
                        end
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
    -- Print welcome message
    local version = ns.Constants and ns.Constants.ADDON_VERSION or "Unknown"
    _G.print(string.format("|cff9370DBWelcome to Warband Nexus v%s|r", version))
    _G.print("|cff9370DBPlease type |r|cff00ccff/wn|r |cff9370DBto open the interface.|r")
    
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
            -- Only print if something was cleaned (debug mode only)
            if result and (result.duplicates > 0 or result.invalidEntries > 0 or result.deprecatedStorage > 0) then
                local debugMode = self.db and self.db.profile and self.db.profile.debugMode
                if debugMode then
                    ns.DebugPrint(string.format("|cff00ff00[WN]|r Database cleaned: %d duplicate(s), %d invalid(s), %d deprecated storage(s)", 
                        result.duplicates, result.invalidEntries, result.deprecatedStorage))
                    ns.DebugPrint("|cff00ff00[WN]|r Changes will persist after /reload")
                end
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
    
    -- Chat message notifications are handled by ChatMessageService.lua
    -- (WN_REPUTATION_GAINED, WN_CURRENCY_GAINED listeners moved there for maintainability)
    
    -- Register PLAYER_ENTERING_WORLD event for notifications and PvE data collection
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    
    -- Initialize Chat Filter (suppress Blizzard rep/currency messages if addon notifications enabled)
    C_Timer.After(0.5, function()
        if self and self.InitializeChatFilter then
            self:InitializeChatFilter()
        end
    end)
    
    -- Initialize Chat Message Service (reputation/currency gain notifications)
    C_Timer.After(0.6, function()
        if self and self.InitializeChatMessageService then
            self:InitializeChatMessageService()
        end
    end)
    
    -- Initialize Reputation Cache (Direct DB architecture)
    if ns.ReputationCache then
        ns.ReputationCache:Initialize()
    end
    
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
                        ns.DebugPrint("|cff00ff00[WN Core]|r " .. collectionType .. " collected: ID=" .. tostring(itemID))
                        
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
                    -- Transmog collection updated (verbose logging removed)
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
    
    -- M+ completion events moved to PvECacheService (RegisterPvECacheEvents)
    
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
-- MOVED: GetBagFingerprint() → Utilities.lua
function WarbandNexus:GetBagFingerprint()
    return ns.Utilities:GetBagFingerprint()
end

--[[
    Handler for inventory bag changes (BAG_UPDATE_DELAYED)
    Scans character bags when bag operations complete
    Optimized for bulk operations (loot, mail, vendor)
]]
function WarbandNexus:OnInventoryBagsChanged()
    local debugMode = self.db and self.db.profile and self.db.profile.debugMode
    
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- Only scan if module enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.items then
        if debugMode then
            ns.DebugPrint("|cffff0000[WN Core]|r OnInventoryBagsChanged: Items module DISABLED")
        end
        return
    end
    
    -- Only auto-scan if enabled
    if not self.db.profile.autoScan then
        if debugMode then
            ns.DebugPrint("|cffff0000[WN Core]|r OnInventoryBagsChanged: AutoScan DISABLED")
        end
        return
    end
    
    if debugMode then
        ns.DebugPrint("|cff9370DB[WN Core]|r OnInventoryBagsChanged: Checking fingerprint...")
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
        if debugMode then
            ns.DebugPrint("|cffff9900[WN Core]|r OnInventoryBagsChanged: Fingerprint unchanged, skipping scan")
        end
        return
    end
    
    if debugMode then
        ns.DebugPrint("|cff00ff00[WN Core]|r OnInventoryBagsChanged: Fingerprint CHANGED! Scheduling scan...")
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
        -- Executing ScanCharacterBags() (verbose logging removed)
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

-- MOVED: OnMoneyChanged() → EventManager.lua
-- MOVED: OnCurrencyChanged() → EventManager.lua
-- Note: These are now in EventManager where they belong with other event handlers
-- MOVED: CHALLENGE_MODE_COMPLETED() → EventManager.lua
-- MOVED: MYTHIC_PLUS_NEW_WEEKLY_RECORD() → EventManager.lua

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
            -- AUTOMATIC: Start PvE data collection (uses PvECacheService)
            if self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.pve then
                -- Wait 3 seconds for API to be ready, then collect PvE data
                C_Timer.After(3, function()
                    if self and self.UpdatePvEData then
                        -- This collects data for current character and saves to DB
                        self:UpdatePvEData()
                    end
                end)
            end
        end
    end
    
    -- Scan character inventory bags on login (after 1 second)
    C_Timer.After(1, function()
        -- GUARD: Only process if character is tracked
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end
        
        if WarbandNexus and WarbandNexus.ScanCharacterBags then
            WarbandNexus:Debug("[LOGIN] Triggering character bag scan")
            WarbandNexus:ScanCharacterBags()
        end
    end)
    
    -- Scan reputations on login (after 3 seconds to ensure API is ready)
    C_Timer.After(3, function()
        -- GUARD: Only process if character is tracked
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end
        
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
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    local charKey = ns.Utilities:GetCharacterKey()
    
    if not self.db.global.characters or not self.db.global.characters[charKey] then
        return
    end
    
    ns.DebugPrint("|cff9370DB[WN Core]|r PvE data changed event - delegating to DataService")
    
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

-- MOVED: OnKeystoneChanged() → EventManager.lua

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
    ns.DebugPrint("|cff9370DB[WN Core]|r Collection changed event (" .. event .. ") - invalidating cache")
    
    -- DISABLED: Bag scan now handles all notifications
    -- Event handlers disabled to prevent duplicates (see CollectionService.lua)
    -- if event == "NEW_MOUNT_ADDED" then
    --     if self.OnNewMount then
    --         self:OnNewMount(event)
    --     end
    -- elseif event == "NEW_PET_ADDED" then
    --     if self.OnNewPet then
    --         self:OnNewPet(event)
    --     end
    -- elseif event == "NEW_TOY_ADDED" then
    --     if self.OnNewToy then
    --         self:OnNewToy(event)
    --     end
    -- end
    
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
        ns.DebugPrint("|cff9370DB[WN Core]|r Pet list changed - invalidating cache")
        
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
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
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
    TAB SWITCH ABORT PROTOCOL
    Prevents race conditions when user switches tabs rapidly
============================================================================]]

-- Track active timers per tab
local activeTabTimers = {}  -- [tabKey] = {timer1, timer2, ...}

---Abort all async operations for a specific tab
---@param tabKey string Tab identifier (e.g., "plans", "storage")
function WarbandNexus:AbortTabOperations(tabKey)
    if not tabKey then return end
    
    -- Cancel all active timers for this tab
    if activeTabTimers[tabKey] then
        local timerCount = #activeTabTimers[tabKey]
        for _, timerHandle in ipairs(activeTabTimers[tabKey]) do
            if timerHandle and timerHandle.Cancel then
                pcall(function() timerHandle:Cancel() end)
            end
        end
        activeTabTimers[tabKey] = {}
        
        -- Log timer cancellations (if any)
        if timerCount > 0 then
            ns.DebugPrint("|cffffcc00[WN Core]|r Cancelled " .. timerCount .. " active timer(s) for tab: " .. tabKey)
        end
    end
    
    -- Abort API operations based on tab type (silent - services will log if interrupted)
    if tabKey == "plans" then
        -- Abort CollectionService coroutines (Mounts, Pets, Toys, Achievements)
        if self.AbortCollectionScans then
            self:AbortCollectionScans()
        end
    elseif tabKey == "reputations" then
        -- Abort ReputationCacheService operations
        if self.AbortReputationOperations then
            self:AbortReputationOperations()
        end
    elseif tabKey == "currency" or tabKey == "currencies" then
        -- Abort CurrencyCacheService operations
        if self.AbortCurrencyOperations then
            self:AbortCurrencyOperations()
        end
    end
end

---Register a timer for a specific tab (so it can be cancelled on tab switch)
---@param tabKey string Tab identifier
---@param timerHandle table Timer handle from C_Timer
function WarbandNexus:RegisterTabTimer(tabKey, timerHandle)
    if not tabKey or not timerHandle then return end
    
    if not activeTabTimers[tabKey] then
        activeTabTimers[tabKey] = {}
    end
    
    table.insert(activeTabTimers[tabKey], timerHandle)
end

---Check if we're still on the expected tab (for async callbacks)
---@param expectedTab string Expected tab identifier
---@return boolean stillOnTab True if still on the same tab
function WarbandNexus:IsStillOnTab(expectedTab)
    if not self.UI or not self.UI.mainFrame then return false end
    return self.UI.mainFrame.currentTab == expectedTab
end

--[[============================================================================
    NOTE: Additional delegate functions and utility wrappers are defined at the
    top of this file under "DELEGATE FUNCTIONS - Service Calls" section.
    
    Stub implementations are in their respective service modules:
    - ScanWarbandBank() → Modules/DataService.lua
    - ToggleMainWindow() → Modules/UI.lua
    - OpenDepositQueue() → Modules/Banker.lua
    - SearchItems() → Modules/UI.lua
============================================================================]]
