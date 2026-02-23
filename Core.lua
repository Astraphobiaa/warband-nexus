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
        debugMode = false,         -- Debug logging (verbose)
        debugTryCounterLoot = false,  -- Loot flow debug only (no rep/currency cache spam)
        
        -- Module toggles (disable to stop API calls for that feature)
        modulesEnabled = {
            items = true,        -- Bank items scanning and display
            storage = true,      -- Cross-character storage browser
            pve = true,          -- Great Vault, M+, Lockouts tracking
            currencies = true,   -- Currency tracking
            reputations = true,  -- Reputation tracking
            plans = true,        -- Collection plans and goals
            professions = true,  -- Profession tracking and companion window
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
        scrollSpeed = 1.0,         -- Scroll speed multiplier (1.0 = default 28px per step)
        
        -- Theme Colors (RGB 0-1 format) - All calculated from master color
        themeColors = {
            accent = {0.40, 0.20, 0.58},      -- Master theme color (purple)
            accentDark = {0.28, 0.14, 0.41},  -- Darker variation (0.7x)
            border = {0.20, 0.20, 0.25},      -- Desaturated border
            tabActive = {0.20, 0.12, 0.30},   -- Active tab background (0.5x)
            tabHover = {0.24, 0.14, 0.35},    -- Hover tab background (0.6x)
        },
        showItemCount = true,
        recipeCompanionEnabled = true,
        
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
            showMountNotifications = true,     -- Show mount notifications
            showPetNotifications = true,       -- Show pet notifications
            showToyNotifications = true,       -- Show toy notifications
            showTransmogNotifications = true,  -- Show transmog/appearance notifications
            showTitleNotifications = true,     -- Show title notifications
            showIllusionNotifications = true,  -- Show illusion notifications
            showAchievementNotifications = true, -- Show achievement notifications
            hideBlizzardAchievementAlert = true, -- Hide Blizzard's default achievement popup (use ours instead)
            showReputationGains = true,        -- Show reputation gain chat messages
            showCurrencyGains = true,          -- Show currency gain chat messages
            popupDuration = 5,                 -- Popup auto-dismiss in seconds (Blizzard default ~5s)
            popupPoint = "TOP",                -- Anchor point on UIParent (TOP, BOTTOM, CENTER, etc.)
            popupX = 0,                        -- X offset from anchor point
            popupY = -100,                     -- Y offset from anchor point
            popupGrowth = "AUTO",              -- Growth direction: "AUTO" (smart), "DOWN", "UP"
            screenFlashEffect = true,          -- Screen flash effect on collectible obtained
            autoTryCounter = true,             -- Automatic try counter for NPC/boss/fishing/container drops
            lastSeenVersion = "0.0.0",         -- Last addon version seen
            lastVaultCheck = 0,                -- Last time vault was checked
            dismissedNotifications = {},       -- Array of dismissed notification IDs
        },
        
        -- Font Management (Resolution-aware scaling)
        fonts = {
            fontFace = "Friz Quadrata TT",  -- LSM key; default font
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
        -- Plans Tracker popup position (AllTheThings-style floating window)
        plansTracker = {
            point = "CENTER",
            x = 0,
            y = 0,
            width = 380,
            height = 420,
        },

        -- Try counter (mount/pet/toy/illusion) - manual or LOOT_OPENED
        tryCounts = {
            mount = {},
            pet = {},
            toy = {},
            illusion = {},
        },
        
        -- ========== TRACK ITEM DB (User overlays on CollectibleSourceDB) ==========
        -- Custom entries added by the user, and built-in entries disabled by the user.
        trackDB = {
            custom = {
                npcs = {},      -- { [npcID] = { { type, itemID, name, [repeatable] }, ... , [statisticIds] } }
                objects = {},   -- { [objectID] = { { type, itemID, name, [repeatable] }, ... } }
            },
            disabled = {},      -- { ["npc:NPCID:ITEMID"] = true, ["object:OBJID:ITEMID"] = true }
        },
        
        -- ========== STATISTICS SNAPSHOTS (Per-character WoW Statistics) ==========
        -- Each character stores their own statistics on login, then we SUM across all.
        -- Key: charKey (e.g. "Charname-Realm"), Value: { [tryKey] = statTotal }
        statisticSnapshots = {},
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
    → Modules/DebugService.lua: Debug, PrintCharacterList, PrintPvEData, PrintBankDebugInfo, ForceScanWarbandBank, WipeAllData
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
        local didReset = ns.MigrationService:RunMigrations(self.db)
        if didReset then
            -- Schema was reset. Block ALL further initialization and reload immediately.
            -- This prevents tracking popups, data scans, and stale cache usage.
            self._pendingSchemaReload = true
            
            -- Re-apply global and char defaults after full schema reset.
            -- AceDB only auto-applies profile defaults; global/char need manual seeding.
            for k, v in pairs(defaults.global) do
                if self.db.global[k] == nil then
                    if type(v) == "table" then
                        self.db.global[k] = {}
                    else
                        self.db.global[k] = v
                    end
                end
            end
            for k, v in pairs(defaults.char) do
                if self.db.char[k] == nil then
                    if type(v) == "table" then
                        self.db.char[k] = {}
                    else
                        self.db.char[k] = v
                    end
                end
            end
            -- ReloadUI will be triggered from OnEnable after game is fully loaded.
            -- Do NOT return here - let OnInitialize finish so raw event frame is registered.
        end
    else
        self:Print("|cffff0000ERROR: MigrationService not loaded!|r")
    end
    
    -- Ensure trackDB nested structure always exists (safe for existing installs)
    if self.db and self.db.global then
        if not self.db.global.trackDB then self.db.global.trackDB = {} end
        if not self.db.global.trackDB.custom then self.db.global.trackDB.custom = {} end
        if not self.db.global.trackDB.custom.npcs then self.db.global.trackDB.custom.npcs = {} end
        if not self.db.global.trackDB.custom.objects then self.db.global.trackDB.custom.objects = {} end
        if not self.db.global.trackDB.disabled then self.db.global.trackDB.disabled = {} end
        if not self.db.global.statisticSnapshots then self.db.global.statisticSnapshots = {} end
    end
    
    -- [DEPRECATED] CollectionScanner removed - now using CollectionService
    -- CollectionService auto-initializes and loads cache from DB
    -- See: InitializationService:InitializeDataServices()
    
    -- =========================================================================
    -- TAINT SUPPRESSION: ADDON_ACTION_FORBIDDEN popup prevention
    -- =========================================================================
    -- Strategy: hooksecurefunc (post-hook, taint-safe) + event-based hide.
    -- NEVER replace StaticPopup_Show directly — that taints the entire popup
    -- system and breaks Blizzard UI (PurchaseBankTab, UpgradeItem, etc.).
    -- =========================================================================
    if not self._taintSuppressInstalled then
        self._taintSuppressInstalled = true

        -- Post-hook: runs AFTER StaticPopup_Show without tainting it.
        -- The popup briefly appears, then we hide it on the same frame.
        hooksecurefunc("StaticPopup_Show", function(which, text_arg1)
            if which == "ADDON_ACTION_FORBIDDEN" and text_arg1 == ADDON_NAME then
                -- Find and hide the popup we just created
                for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
                    local popup = _G["StaticPopup" .. i]
                    if popup and popup:IsShown() then
                        local txt = popup.text and popup.text.GetText and popup.text:GetText() or ""
                        if txt:find(ADDON_NAME) or txt:find("WarbandNexus") then
                            popup:Hide()
                            local debugMode = WarbandNexus and WarbandNexus.db
                                and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode
                            if debugMode then
                                _G.print("|cff9370DB[WN Taint]|r Suppressed ADDON_ACTION_FORBIDDEN popup")
                            end
                            break
                        end
                    end
                end
            end
        end)

        -- Event-based safety net: catches any popups the post-hook missed
        local taintFrame = CreateFrame("Frame")
        taintFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
        taintFrame:SetScript("OnEvent", function(frame, event, addonName, blockedFunc)
            if addonName == ADDON_NAME then
                local debugMode = WarbandNexus and WarbandNexus.db
                    and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode
                if debugMode then
                    _G.print("|cff9370DB[WN Taint]|r ADDON_ACTION_FORBIDDEN event: " .. tostring(blockedFunc))
                end
                C_Timer.After(0.05, function()
                    for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
                        local popup = _G["StaticPopup" .. i]
                        if popup and popup:IsShown() then
                            local txt = popup.text and popup.text.GetText and popup.text:GetText() or ""
                            if txt:find(ADDON_NAME) or txt:find("WarbandNexus") then
                                popup:Hide()
                                if debugMode then
                                    _G.print("|cff9370DB[WN Taint]|r Safety net: hid popup #" .. i)
                                end
                                break
                            end
                        end
                    end
                end)
            end
        end)
    end
    
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
                            
                            -- NOTE: Notifications are now triggered by:
                            -- 1. InitializationService (returning users - faster path at T+2.0s)
                            -- 2. CharacterService:ConfirmCharacterTracking (first-time users - after popup)
                            -- CheckNotificationsOnLogin() is idempotent, so no double-fire risk
                        end
                    end
                end)
            else
                -- Reload UI: Save character data (but respect tracking confirmation flow)
                C_Timer.After(2, function()
                    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
                        return
                    end
                    
                    -- CRITICAL: Only save if tracking has been confirmed by the user.
                    -- After a schema reset + reload, the tracking popup hasn't appeared yet
                    -- at t=2s (it shows at t=2.5s). Saving here with trackingConfirmed=true
                    -- would permanently skip the popup, leaving the character untracked.
                    local charKey = ns.Utilities:GetCharacterKey()
                    local charData = charKey and WarbandNexus.db.global.characters
                        and WarbandNexus.db.global.characters[charKey]
                    
                    if charData and charData.trackingConfirmed then
                        if WarbandNexus.SaveCharacter then
                            WarbandNexus:SaveCharacter()
                        end
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
    
    -- Register TIME_PLAYED_MSG for played time tracking
    self:RegisterEvent("TIME_PLAYED_MSG", "OnTimePlayedReceived")
    
    -- Initialize minimap button (LibDBIcon) via InitializationService
    if ns.InitializationService then
        ns.InitializationService:InitializeMinimapButton(self)
    end
    
    print("|cffff00ff[CORE] About to initialize Gold Management Service...")
    print("|cffff00ff[CORE] self.InitializeGoldManagementService exists?", self.InitializeGoldManagementService and "YES" or "NO")
    
    -- Initialize Gold Management Service
    if self.InitializeGoldManagementService then
        print("|cffff00ff[CORE] Calling InitializeGoldManagementService...")
        self:InitializeGoldManagementService()
        print("|cffff00ff[CORE] InitializeGoldManagementService DONE")
    else
        print("|cffff0000[CORE] ERROR: InitializeGoldManagementService NOT FOUND!")
    end
    
end

--[[
    Enable the addon
    Called when the addon becomes enabled
]]
function WarbandNexus:OnEnable()
    -- If schema reset is pending, block all initialization and ask user to reload.
    -- Taint: ReloadUI() is protected; addon code is tainted (timers, events, OnUpdate).
    -- Only user-initiated execution (button click) can call protected functions.
    -- See: https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting
    -- We create a branded dialog with a reload button — click triggers ReloadUI().
    if self._pendingSchemaReload then
        C_Timer.After(2, function()
            -- Prevent duplicate dialogs
            if _G["WarbandNexusSchemaReloadDialog"] and _G["WarbandNexusSchemaReloadDialog"]:IsShown() then
                return
            end

            local COLORS = ns.UI_COLORS or { accent = {0.42, 0.05, 0.85} }
            local FontManager = ns.FontManager

            -- Main dialog frame (matches TrackingConfirmation pattern)
            local dialog = CreateFrame("Frame", "WarbandNexusSchemaReloadDialog", UIParent, "BackdropTemplate")
            dialog:SetSize(420, 200)
            dialog:SetPoint("CENTER", 0, 120)
            dialog:SetFrameStrata("FULLSCREEN_DIALOG")
            dialog:SetFrameLevel(500)

            dialog:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = false,
                tileSize = 1,
                edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 }
            })
            dialog:SetBackdropColor(0.05, 0.05, 0.07, 1)
            dialog:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

            dialog:SetMovable(true)
            dialog:EnableMouse(true)
            dialog:RegisterForDrag("LeftButton")
            dialog:SetScript("OnDragStart", dialog.StartMoving)
            dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

            -- Title
            local titleText = FontManager and FontManager:CreateFontString(dialog, "header", "OVERLAY")
                or dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            titleText:SetPoint("TOP", 0, -20)
            titleText:SetText("|cff9370DBWarband Nexus|r")

            -- Update icon (atlas)
            local updateIcon = dialog:CreateTexture(nil, "ARTWORK")
            updateIcon:SetSize(32, 32)
            updateIcon:SetPoint("TOP", titleText, "BOTTOM", 0, -12)
            pcall(function() updateIcon:SetAtlas("UI-HUD-MicroMenu-Questlog-Mouseover", false) end)

            -- Description
            local descText = FontManager and FontManager:CreateFontString(dialog, "body", "OVERLAY")
                or dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            descText:SetPoint("TOP", updateIcon, "BOTTOM", 0, -10)
            descText:SetWidth(380)
            descText:SetJustifyH("CENTER")
            descText:SetText("|cffffffff" .. ((ns.L and ns.L["DATABASE_UPDATED_MSG"]) or "Database updated to a new version.") .. "|r\n|cffaaaaaa" .. ((ns.L and ns.L["DATABASE_RELOAD_REQUIRED"]) or "A one-time reload is required to apply changes.") .. "|r")

            -- Reload button (accent colored, hover effect)
            local reloadBtn = CreateFrame("Button", nil, dialog, "BackdropTemplate")
            reloadBtn:SetSize(200, 40)
            reloadBtn:SetPoint("BOTTOM", 0, 20)
            reloadBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false,
                edgeSize = 2,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            reloadBtn:SetBackdropColor(COLORS.accent[1] * 0.4, COLORS.accent[2] * 0.4, COLORS.accent[3] * 0.4, 1)
            reloadBtn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

            local btnText = FontManager and FontManager:CreateFontString(reloadBtn, "header", "OVERLAY")
                or reloadBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            btnText:SetPoint("CENTER")
            btnText:SetText("|cffffffff" .. ((ns.L and ns.L["RELOAD_UI_BUTTON"]) or "Reload UI") .. "|r")

            reloadBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(COLORS.accent[1] * 0.6, COLORS.accent[2] * 0.6, COLORS.accent[3] * 0.6, 1)
                self:SetBackdropBorderColor(1, 1, 1, 1)
            end)
            reloadBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(COLORS.accent[1] * 0.4, COLORS.accent[2] * 0.4, COLORS.accent[3] * 0.4, 1)
                self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            end)
            reloadBtn:SetScript("OnClick", function()
                ReloadUI()
            end)

            dialog:Show()
        end)
        return
    end
    
    -- Print welcome message
    local version = ns.Constants and ns.Constants.ADDON_VERSION or "Unknown"
    _G.print(string.format("|cff9370DB" .. ((ns.L and ns.L["WELCOME_MSG_FORMAT"]) or "Welcome to Warband Nexus v%s") .. "|r", version))
    _G.print("|cff9370DB" .. ((ns.L and ns.L["WELCOME_TYPE_CMD"]) or "Please type") .. " |r|cff00ccff/wn|r |cff9370DB" .. ((ns.L and ns.L["WELCOME_OPEN_INTERFACE"]) or "to open the interface.") .. "|r")
    
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
            -- Database cleanup completed silently
        end)
    end
    
    -- WN_BAGS_UPDATED UI refresh is handled by UI.lua (SchedulePopulateContent)
    -- Do NOT register here — AceEvent allows only one handler per event per object,
    -- and UI.lua's debounced handler would overwrite this or vice versa.
    
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
        local SafeInit = ns.InitializationService and ns.InitializationService.SafeInit
        if SafeInit then
            SafeInit(function()
                if self and self.InitializeChatMessageService then
                    self:InitializeChatMessageService()
                end
            end, "ChatMessageService")
        else
            if self and self.InitializeChatMessageService then
                self:InitializeChatMessageService()
            end
        end
    end)
    
    -- Initialize Reputation Cache (Direct DB architecture)
    if ns.ReputationCache then
        ns.ReputationCache:Initialize()
    end
    
    -- Collection events: owned by EventManager (debounced) → CollectionService (handlers)
    -- ACHIEVEMENT_EARNED: owned by CollectionService (OnAchievementEarned)
    -- TRANSMOG_COLLECTION_UPDATED: owned by EventManager → CollectionService
    -- NEW_MOUNT_ADDED / NEW_PET_ADDED / NEW_TOY_ADDED: owned by EventManager → CollectionService
    -- Do NOT register here — single-owner pattern prevents duplicate processing
    
    -- CRITICAL: Check for addon conflicts immediately on enable (only if bank module enabled)
    -- This runs on both initial login AND /reload
    -- Detect if user re-enabled conflicting addons/modules
    
    -- Session flag to prevent duplicate saves
    self.characterSaved = false
    
    -- BANKFRAME_OPENED/CLOSED: owned by ItemsCacheService (single owner)
    -- BAG_UPDATE_DELAYED: owned by ItemsCacheService (single owner)
    -- PLAYERBANKSLOTS_CHANGED: owned by ItemsCacheService (single owner)
    -- Do NOT register here — prevents duplicate scanning
    
    -- Guild Bank events (disabled by default, set ENABLE_GUILD_BANK=true to enable)
    if ENABLE_GUILD_BANK then
        self:RegisterEvent("GUILDBANKFRAME_OPENED", "OnGuildBankOpened")
        self:RegisterEvent("GUILDBANKFRAME_CLOSED", "OnGuildBankClosed")
        self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", "OnBagUpdate") -- Guild bank slot changes
    end
    
    self:RegisterEvent("PLAYER_MONEY", "OnMoneyChanged")
    self:RegisterEvent("ACCOUNT_MONEY", "OnMoneyChanged") -- Warband Bank gold changes
    
    -- CURRENCY_DISPLAY_UPDATE: owned by CurrencyCacheService (FIFO queue + drain)
    -- Do NOT register here — single owner prevents duplicate processing
    
    -- M+ completion events moved to PvECacheService (RegisterPvECacheEvents)
    
    -- Combat protection for UI (taint prevention: we only Hide/Show our own frame, no secure frames)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart") -- Entering combat
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")  -- Leaving combat
    
    -- PvE events managed by EventManager (throttled)
    
    -- BAG_UPDATE: owned by ItemsCacheService (0.5s bucket, single owner)
    -- Collection events: owned by EventManager (debounced)
    
    -- WN_BAGS_UPDATED UI refresh is handled by UI.lua (coalesced with other events)
    -- Do NOT add a duplicate listener here -- it causes double PopulateContent calls
    
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
    -- Save runtime-discovered NPC names to cache for next session
    if self._saveNpcNameCache then
        self._saveNpcNameCache()
    end
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

function WarbandNexus:PrintCharacterList()
    ns.DebugService:PrintCharacterList(self)
end

function WarbandNexus:PrintPvEData()
    ns.DebugService:PrintPvEData(self)
end

function WarbandNexus:Debug(message, ...)
    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
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
    BANKFRAME_OPENED/CLOSED: owned by ItemsCacheService
    See Modules/ItemsCacheService.lua OnBankOpened() / OnBankClosed()
============================================================================]]

-- GetBagFingerprint: REMOVED — Dead code, never called.
-- ItemsCacheService uses hash-based change detection (GenerateItemHash) instead.

-- OnInventoryBagsChanged: MOVED to ItemsCacheService (single owner for BAG_UPDATE_DELAYED)

--[[============================================================================
    GUILD BANK HANDLERS
============================================================================]]
function WarbandNexus:OnGuildBankOpened()
    self.guildBankIsOpen = true
    
    -- Scan guild bank
    if self.ScanGuildBank then
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
    ns.DebugPrint("|cff9370DB[WN Core]|r [World Event] PLAYER_ENTERING_WORLD triggered (login=" .. tostring(isInitialLogin) .. ", reload=" .. tostring(isReloadingUi) .. ")")
    
    -- Run on BOTH initial login AND reload.
    -- PRIORITY TIERS (Core handles game data collection after DataServices):
    --   DataServices (T+0.5..3s): handled by InitializationService
    --   Core P0 (T+4s):   Lightweight resets + profession basics (batched, <3ms)
    --   Core P1 (T+5s):   Expansion professions (moderate)
    --   Core P2 (T+5.5s): PvE data + Knowledge (batched, needs PvECache from T+2s)
    --   Core P3 (T+6.5s): Plan tracking (initial login only, low priority)
    if isInitialLogin or isReloadingUi then
        local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)

        -- Only register tracked-character loading operations if actually tracked.
        -- Account-wide ops (collections, try counts) always run regardless.
        local LT = ns.LoadingTracker
        if isTracked then
            if LT then
                LT:Register("professions", (ns.L and ns.L["LT_PROFESSIONS"]) or "Professions")
                LT:Register("pve", (ns.L and ns.L["LT_PVE_DATA"]) or "PvE Data")
            end
        end
        
        -- Core P0 (T+4s): Lightweight resets (always) + character-specific data (tracked only)
        C_Timer.After(4, function()
            if self and self.CheckWeeklyReset then self:CheckWeeklyReset() end
            if self and self.CheckRecurringPlanResets then self:CheckRecurringPlanResets() end

            -- Character-specific: skip for untracked characters
            local tracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
            if tracked then
                if self and self.RequestPlayedTime then self:RequestPlayedTime() end
                local P = ns.Profiler
                if P then P:Start("CollectConcentration") end
                if self and self.CollectConcentrationOnLogin then self:CollectConcentrationOnLogin() end
                if P then P:Stop("CollectConcentration") end
                if P then P:Start("CollectEquipment") end
                if self and self.CollectEquipmentOnLogin then self:CollectEquipmentOnLogin() end
                if P then P:Stop("CollectEquipment") end
            end
        end)
        
        -- Core P1 (T+5s): Expansion sub-profession data (tracked only)
        C_Timer.After(5, function()
            local tracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
            if tracked then
                local P = ns.Profiler
                if P then P:Start("CollectExpansionProfessions") end
                if self and self.CollectExpansionProfessionsOnLogin then
                    self:CollectExpansionProfessionsOnLogin()
                end
                if P then P:Stop("CollectExpansionProfessions") end
            end
            local LT = ns.LoadingTracker
            if LT then LT:Complete("professions") end
        end)
        
        -- Core P2 (T+5.5s): PvE data + Knowledge (tracked only)
        C_Timer.After(5.5, function()
            local tracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
            if tracked then
                if self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.pve then
                    local P = ns.Profiler
                    if P then P:Start("UpdatePvEData") end
                    if self and self.UpdatePvEData then self:UpdatePvEData() end
                    if P then P:Stop("UpdatePvEData") end
                end

                local P = ns.Profiler
                if P then P:Start("CollectKnowledge") end
                if self and self.CollectKnowledgeOnLogin then self:CollectKnowledgeOnLogin() end
                if P then P:Stop("CollectKnowledge") end
            end
            local LT = ns.LoadingTracker
            if LT then LT:Complete("pve") end
        end)
    end
    
    -- Core P3 (T+6.5s): Plan tracking — lowest priority, initial login only
    if isInitialLogin then
        C_Timer.After(6.5, function()
            local SafeInit = ns.InitializationService and ns.InitializationService.SafeInit
            if SafeInit then
                SafeInit(function()
                    if WarbandNexus and WarbandNexus.InitializePlanTracking then
                        WarbandNexus:InitializePlanTracking()
                    end
                end, "PlanTracking")
            else
                if WarbandNexus and WarbandNexus.InitializePlanTracking then
                    WarbandNexus:InitializePlanTracking()
                end
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
    Hides ALL addon windows to prevent taint issues.
    Tracks which windows were open so they can be restored after combat.
]]

-- Restorable windows: global frame names for windows that should be restored after combat
local RESTORABLE_WINDOWS = {
    "WarbandNexusSettingsFrame",
    "WarbandNexus_PlansTracker",
}

-- Ephemeral windows: global frame names for windows that should just close (not restore)
-- RecipeCompanion is ephemeral because it's anchored to ProfessionsFrame which Blizzard may close
local EPHEMERAL_WINDOWS = {
    "WarbandNexus_RecipeCompanion",
    "WNTryCountPopup",
    "WarbandNexus_WeeklyPlanDialog",
    "WarbandNexus_DailyPlanDialog",
    "WarbandNexus_CustomPlanDialog",
    "WarbandNexusInfoDialog",
    "WarbandNexusUpdateBackdrop",
}

function WarbandNexus:OnCombatStart()
    ns.DebugPrint("|cff9370DB[WN Core]|r [Combat Event] PLAYER_REGEN_DISABLED triggered")
    
    local anythingHidden = false
    self._windowsHiddenByCombat = self._windowsHiddenByCombat or {}
    wipe(self._windowsHiddenByCombat)
    
    -- Hide main UI during combat (taint protection)
    if self.mainFrame and self.mainFrame:IsShown() then
        self.mainFrame:Hide()
        self._windowsHiddenByCombat["mainFrame"] = true
        anythingHidden = true
    end
    
    -- Hide restorable windows (will be re-shown after combat)
    for _, globalName in ipairs(RESTORABLE_WINDOWS) do
        local frame = _G[globalName]
        if frame and frame:IsShown() then
            frame:Hide()
            self._windowsHiddenByCombat[globalName] = true
            anythingHidden = true
        end
    end
    
    -- Hide ephemeral windows (NOT restored after combat)
    for _, globalName in ipairs(EPHEMERAL_WINDOWS) do
        local frame = _G[globalName]
        if frame and frame:IsShown() then
            if frame.Close then
                frame.Close()
            else
                frame:Hide()
            end
        end
    end
    
    -- Hide position ghost if active
    if self._positionGhost and self._positionGhost:IsShown() then
        self._positionGhost:Hide()
    end
    
    -- Hide custom tooltip (from TooltipService)
    if ns.TooltipService and ns.TooltipService.Hide then
        ns.TooltipService:Hide()
    end
    
    if anythingHidden then
        self:Print("|cffff6600UI hidden during combat.|r")
    end
end

--[[
    Called when combat ends (PLAYER_REGEN_ENABLED)
    Restores windows that were hidden by combat.
]]
function WarbandNexus:OnCombatEnd()
    ns.DebugPrint("|cff9370DB[WN Core]|r [Combat Event] PLAYER_REGEN_ENABLED triggered")
    
    local hidden = self._windowsHiddenByCombat
    if hidden then
        -- Restore main frame
        if hidden["mainFrame"] and self.mainFrame then
            self.mainFrame:Show()
        end
        
        -- Restore restorable windows
        for _, globalName in ipairs(RESTORABLE_WINDOWS) do
            if hidden[globalName] then
                local frame = _G[globalName]
                if frame then
                    frame:Show()
                end
            end
        end
        
        wipe(hidden)
    end
    
    -- pendingBagUpdateAfterCombat: REMOVED — never set anywhere in the codebase.
    -- ItemsCacheService handles all bag events independently (including post-combat).
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

-- OnBagUpdate: REMOVED — Dead code. ItemsCacheService defines WarbandNexus:OnBagUpdate()
-- which loads AFTER Core.lua and overwrites this method. All BAG_UPDATE handling is now
-- owned by ItemsCacheService (hash-based change detection + throttled incremental updates).
-- See Modules/ItemsCacheService.lua: OnBagUpdate(), ThrottledBagUpdate(), UpdateSingleBag().

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
        
        -- Timer cancellations handled silently
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
    - ScanWarbandBank() → Modules/ItemsCacheService.lua (overwrites DataService version)
    - ToggleMainWindow() → Modules/UI.lua
    - OpenDepositQueue() → Modules/Banker.lua
    - SearchItems() → Modules/UI.lua
============================================================================]]
