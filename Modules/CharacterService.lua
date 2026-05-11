--[[
    Warband Nexus - Character Service
    Manages character tracking, favorites, and character-specific operations
    Extracted from Core.lua for proper separation of concerns
]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue
local E = ns.Constants.EVENTS
local tremove = table.remove
local wipe = table.wipe

-- Debug print helper
local DebugPrint = ns.DebugPrint
---@class CharacterService
local CharacterService = {}
ns.CharacterService = CharacterService

--- Key used in `profile.characterGroupAssignments` (canonical when Utilities is available).
local function AssignKeyFromCharKey(charKey)
    if not charKey or charKey == "" then return nil end
    local GetCanon = ns.Utilities and ns.Utilities.GetCanonicalCharacterKey
    if not GetCanon then return charKey end
    local c = GetCanon(charKey)
    if c and c ~= "" then
        return c
    end
    return charKey
end

local function ClearBothAssignKeys(assign, charKey)
    if not assign or not charKey or charKey == "" then return end
    local k1 = charKey
    local k2 = AssignKeyFromCharKey(charKey)
    assign[k1] = nil
    if k2 and k2 ~= k1 then
        assign[k2] = nil
    end
end

--============================================================================
-- CHARACTER TRACKING
--============================================================================

---Confirm character tracking status and update database
---@param addon table The WarbandNexus addon instance
---@param charKey string Character key ("Name-Realm")
---@param isTracked boolean Whether to track this character
function CharacterService:ConfirmCharacterTracking(addon, charKey, isTracked)
    if not addon.db or not addon.db.global then return end
    
    -- Initialize character entry if it doesn't exist
    if not addon.db.global.characters then
        addon.db.global.characters = {}
    end
    
    if not addon.db.global.characters[charKey] then
        addon.db.global.characters[charKey] = {}
    end
    local entry = addon.db.global.characters[charKey]
    if not entry.name or not entry.realm then
        local un = UnitName("player")
        if un and type(un) == "string" and not (issecretvalue and issecretvalue(un)) then
            entry.name = un
        end
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        if not realm or (issecretvalue and issecretvalue(realm)) then
            realm = GetRealmName and GetRealmName()
        end
        if realm and not (issecretvalue and issecretvalue(realm)) then
            entry.realm = realm
        end
    end
    entry.isTracked = isTracked
    entry.lastSeen = time()
    entry.trackingConfirmed = true  -- User made a choice, don't ask again
    
    -- HYBRID: Broadcast event for modules to react (event-driven component)
    addon:SendMessage(E.CHARACTER_TRACKING_CHANGED, {
        charKey = charKey,
        isTracked = isTracked
    })
    
    if isTracked then
        addon:Print("|cff00ff00" .. ((ns.L and ns.L["TRACKING_ENABLED_CHAT"]) or "Character tracking enabled. Data collection will begin.") .. "|r")
        
        -- Register loading tracker for post-confirmation data collection.
        -- Account-wide ops (collections, trycounts) are already registered/completed.
        -- These are character-specific operations that were skipped during init.
        local LT = ns.LoadingTracker
        if LT then
            LT:Register("character", (ns.L and ns.L["LT_CHARACTER_DATA"]) or "Character Data")
            LT:Register("caches", (ns.L and ns.L["LT_CURRENCY_CACHES"]) or "Currency & Caches")
            LT:Register("reputations", (ns.L and ns.L["LT_REPUTATIONS"]) or "Reputations")
            LT:Register("professions", (ns.L and ns.L["LT_PROFESSIONS"]) or "Professions")
            LT:Register("pve", (ns.L and ns.L["LT_PVE_DATA"]) or "PvE Data")
        end
        
        -- CRITICAL: Reset characterSaved flag (in case of DB wipe without reload)
        addon.characterSaved = false
        
        -- STEP 1: Register event listeners + character cache (skipped during init)
        -- Wrapped in SafeInit: user may confirm tracking while in combat
        local SafeInit = ns.InitializationService and ns.InitializationService.SafeInit
        C_Timer.After(0.05, function()
            local function doStep1()
                local addonInstance = _G.WarbandNexus or addon
                local ok, err = pcall(function()
                    -- Character cache (was skipped in InitializationService P3 because not tracked)
                    if addonInstance and addonInstance.RegisterCharacterCacheEvents then
                        addonInstance:RegisterCharacterCacheEvents()
                    end
                    if addonInstance and addonInstance.GetCharacterData then
                        addonInstance:GetCharacterData(true)
                    end
                    -- Items Cache events (BAG_UPDATE, BANKFRAME_OPENED, etc.)
                    if addonInstance and addonInstance.InitializeItemsCache then
                        addonInstance:InitializeItemsCache()
                    end
                    -- Currency Cache (handles event registration internally, guarded)
                    if addonInstance and addonInstance.InitializeCurrencyCache then
                        addonInstance:InitializeCurrencyCache()
                    end
                    -- PvE Cache events (M+, Vault, etc.)
                    if addonInstance and addonInstance.RegisterPvECacheEvents then
                        addonInstance:RegisterPvECacheEvents()
                    end
                end)
                if not ok and DebugPrint then
                    DebugPrint("|cffff4444[WN CharacterService]|r PostConfirm cache init failed: " .. tostring(err))
                end
                -- Always clear "caches" loading step (combat-deferred SafeInit or pcall failure must not leave UI stuck)
                local LT = ns.LoadingTracker
                if LT then LT:Complete("caches") end
            end
            if SafeInit then SafeInit(doStep1, "PostConfirm:EventListeners") else doStep1() end
        end)
        
        -- STEP 2: Initial character data save (basic info)
        C_Timer.After(0.1, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.SaveCharacter then
                addonInstance:SaveCharacter()
            end
        end)
        
        -- STEP 3: Trigger items scan (fixes ItemsUI empty on first tracking)
        C_Timer.After(0.2, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.ScanInventoryBags then
                local cKey = ns.Utilities:GetCharacterKey()
                addonInstance:ScanInventoryBags(cKey)
                if ns.ItemsLoadingState then
                    ns.ItemsLoadingState.isLoading = false
                    ns.ItemsLoadingState.scanProgress = 100
                    ns.ItemsLoadingState.currentStage = nil
                end
            end
        end)
        
        -- STEP 4: Trigger reputation scan
        C_Timer.After(1, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.ScanReputations then
                addonInstance:ScanReputations()
            end
            -- LT:Complete("reputations") called by PerformFullScan when done
        end)
        
        -- STEP 5: Trigger currency scan
        C_Timer.After(1.5, function()
            if ns.CurrencyCache and ns.CurrencyCache.PerformFullScan then
                ns.CurrencyCache:PerformFullScan(true)
            end
        end)
        
        -- STEP 6: Force item level update
        C_Timer.After(1.2, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.UpdateCharacterCache then
                addonInstance:UpdateCharacterCache("itemLevel")
            end
        end)
        
        -- STEP 7: Re-save character data (ensures all data is fresh)
        C_Timer.After(1.8, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance then
                addonInstance.characterSaved = false
                if addonInstance.SaveCharacter then
                    addonInstance:SaveCharacter()
                end
            end
            local LT = ns.LoadingTracker
            if LT then LT:Complete("character") end
        end)
        
        -- STEP 8: Notify UI to refresh (event-driven; UI listens for WN_CHARACTER_UPDATED)
        C_Timer.After(2.2, function()
            local function doStep8()
                local addonInstance = _G.WarbandNexus or addon
                if addonInstance and addonInstance.SendMessage then
                    local ev = E.CHARACTER_UPDATED
                    addonInstance:SendMessage(ev, { charKey = charKey })
                end
            end
            if SafeInit then SafeInit(doStep8, "PostConfirm:UIRefresh") else doStep8() end
        end)
        
        -- STEP 9: Profession data collection
        -- Core.lua timers (T+4-5s from login) may have already fired before user confirmed.
        -- These functions are safe to call multiple times (idempotent overwrites).
        C_Timer.After(3, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance._coreStartupPhasesPending then
                return
            end
            if addonInstance then
                if addonInstance.CollectConcentrationOnLogin then
                    addonInstance:CollectConcentrationOnLogin()
                end
                if addonInstance.CollectEquipmentOnLogin then
                    addonInstance:CollectEquipmentOnLogin()
                end
            end
        end)
        C_Timer.After(4, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance._coreStartupPhasesPending then
                return
            end
            if addonInstance and addonInstance.CollectExpansionProfessionsOnLogin then
                addonInstance:CollectExpansionProfessionsOnLogin()
            end
            local LT = ns.LoadingTracker
            if LT then LT:Complete("professions") end
        end)
        
        -- STEP 10: PvE data + Knowledge collection
        C_Timer.After(4.5, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance._coreStartupPhasesPending then
                return
            end
            if addonInstance then
                if addonInstance.db and addonInstance.db.profile
                    and addonInstance.db.profile.modulesEnabled
                    and addonInstance.db.profile.modulesEnabled.pve then
                    if addonInstance.UpdatePvEData then
                        addonInstance:UpdatePvEData()
                    end
                end
                if addonInstance.CollectKnowledgeOnLogin then
                    addonInstance:CollectKnowledgeOnLogin()
                end
            end
            local LT = ns.LoadingTracker
            if LT then LT:Complete("pve") end
        end)
        
        -- STEP 11: Played time + profession recharge timer
        -- These were gated on tracking in Core.lua/EventManager.lua
        C_Timer.After(2, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance._coreStartupPhasesPending then
                return
            end
            if addonInstance and addonInstance.db and addonInstance.db.profile
                and addonInstance.db.profile.requestPlayedTimeOnLogin ~= false
                and addonInstance.RequestPlayedTime then
                addonInstance:RequestPlayedTime()
            end
            if addonInstance and addonInstance.StartRechargeTimer then
                addonInstance:StartRechargeTimer()
            end
        end)
        
        -- STEP 12: What's New notification
        C_Timer.After(0.5, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.CheckNotificationsOnLogin then
                addonInstance:CheckNotificationsOnLogin()
            end
        end)
    else
        addon:Print("|cffff8800" .. ((ns.L and ns.L["TRACKING_DISABLED_CHAT"]) or "Character tracking disabled. Running in read-only mode.") .. "|r")
        
        -- Save minimal character data for untracked characters
        addon.characterSaved = false  -- Reset flag
        C_Timer.After(0.1, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.SaveCharacter then
                addonInstance:SaveCharacter()  -- Will call SaveMinimalCharacterData
            end
            
            -- Notify UI to refresh (event-driven; UI listens for WN_CHARACTER_UPDATED)
            C_Timer.After(0.5, function()
                if addonInstance and addonInstance.SendMessage then
                    local ev = E.CHARACTER_UPDATED
                    addonInstance:SendMessage(ev, { charKey = ns.Utilities and ns.Utilities:GetCharacterKey() })
                end
            end)
        end)
        
        -- Show What's New notification even for untracked characters (addon version info)
        -- For first-time installs who chose Untrack: show What's New after popup closes
        C_Timer.After(0.5, function()
            local addonInstance = _G.WarbandNexus or addon
            if addonInstance and addonInstance.CheckNotificationsOnLogin then
                addonInstance:CheckNotificationsOnLogin()
            end
        end)
    end
    
end

---Find db.global.characters index for the logged-in player (raw vs canonical key mismatch breaks lookups).
---@param addon table WarbandNexus
---@return string|nil actualKey Key present in db.global.characters, or nil
function CharacterService:ResolveCharactersTableKey(addon)
    if not addon or not addon.db or not addon.db.global or not addon.db.global.characters then
        return nil
    end
    local chars = addon.db.global.characters
    local rawKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not rawKey or rawKey == "" then
        return nil
    end
    if chars[rawKey] then
        return rawKey
    end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local canon = ns.Utilities:GetCanonicalCharacterKey(rawKey)
        if canon and canon ~= "" and canon ~= rawKey and chars[canon] then
            return canon
        end
    end
    return nil
end

---Check if current character is tracked
---@param addon table The WarbandNexus addon instance
---@return boolean true if tracked, false if untracked or not found
function CharacterService:IsCharacterTracked(addon)
    -- Safety check: addon must exist
    if not addon then
        return false
    end
    
    if not addon.db or not addon.db.global or not addon.db.global.characters then
        return false
    end
    
    local charKey = self:ResolveCharactersTableKey(addon)
    local charData = charKey and addon.db.global.characters[charKey]
    
    -- Default to false for new characters (require explicit opt-in)
    if not charData then
        return false
    end
    
    -- CRITICAL: Explicit true check - only track if user explicitly enabled tracking
    -- nil or false = not tracked (requires user action to enable)
    return charData.isTracked == true
end

---Show character tracking confirmation dialog (Custom UI)
---@param addon table The WarbandNexus addon instance
---@param charKey string Character key ("Name-Realm")
function CharacterService:ShowCharacterTrackingConfirmation(addon, charKey)
    -- CRITICAL: If dialog already exists and is visible, don't create a new one
    if addon.trackingDialog and addon.trackingDialog:IsVisible() then
        return
    end
    
    -- Clean up old StaticPopup if it exists (legacy system)
    StaticPopupDialogs["WARBANDNEXUS_ADD_CHARACTER"] = nil
    
    -- Create custom dialog frame
    local dialog = CreateFrame("Frame", "WarbandNexusTrackingDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(480, 210)  -- Compact size
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")  -- Above everything
    dialog:SetFrameLevel(500)  -- Very high level
    
    -- Backdrop (FULLY OPAQUE - solid background)
    dialog:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",  -- Solid white texture
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false,
        tileSize = 1,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    dialog:SetBackdropColor(0.05, 0.05, 0.07, 1)  -- Alpha = 1 (fully opaque)
    local accentColor = ns.UI_COLORS and ns.UI_COLORS.accent or {0.40, 0.20, 0.58}
    dialog:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
    
    -- Make draggable
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    
    -- NO CLOSE BUTTON - User must make a choice
    
    -- Title (Centered)
    local titleText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    titleText:SetPoint("TOP", 0, -20)
    titleText:SetText("|cff9370DB" .. ((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus") .. "|r")
    
    -- Main question
    local questionText = ns.FontManager:CreateFontString(dialog, "body", "OVERLAY")
    questionText:SetPoint("TOP", titleText, "BOTTOM", 0, -16)
    questionText:SetWidth(460)
    questionText:SetJustifyH("CENTER")
    questionText:SetText((ns.L and ns.L["TRACK_CHARACTER_QUESTION"]) or "Do you want to track this character?")
    
    -- Character name with class color
    local charName = charKey
    local charRealmRaw = nil
    if charKey and not (issecretvalue and issecretvalue(charKey)) then
        charName = charKey:match("^([^%-]+)") or charKey
        charRealmRaw = charKey:match("%-(.+)")
    end
    if not charRealmRaw and GetRealmName then
        charRealmRaw = GetRealmName() or ""
        if issecretvalue and charRealmRaw and issecretvalue(charRealmRaw) then charRealmRaw = "" end
    end
    charRealmRaw = charRealmRaw or ""
    local charRealm = (charRealmRaw ~= "" and ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(charRealmRaw)) or charRealmRaw
    if charName and issecretvalue and issecretvalue(charName) then
        charName = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
    end
    if charRealm and issecretvalue and issecretvalue(charRealm) then
        charRealm = ""
    end
    
    -- Class color from roster (classFile / classID / localized class → Blizzard token)
    local classColor = "|cffffcc00"  -- Default gold when unknown
    if charName and not (issecretvalue and issecretvalue(charName)) and ns.UI_GetClassColorHexForWarbandCharacter then
        local hex = ns.UI_GetClassColorHexForWarbandCharacter(charName)
        if hex and hex ~= "|cffaaaaaa" then
            classColor = hex
        end
    end
    
    local charNameText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    charNameText:SetPoint("TOP", questionText, "BOTTOM", 0, -8)
    charNameText:SetText(classColor .. charName .. " - " .. charRealm .. "|r")
    
    -- Option boxes container
    local optionsY = -20
    
    -- Tracked option (LEFT) - now a BUTTON
    local trackedFrame = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    trackedFrame:SetSize(200, 75)  -- Compact size
    trackedFrame:SetPoint("TOP", charNameText, "BOTTOM", -110, optionsY)
    trackedFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    trackedFrame:SetBackdropColor(0.1, 0.3, 0.2, 1)
    trackedFrame:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
    
    -- Hover effect for Tracked card
    trackedFrame:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.4, 0.25, 1)  -- Brighter on hover
        self:SetBackdropBorderColor(0.3, 0.8, 0.4, 1)
    end)
    trackedFrame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.3, 0.2, 1)
        self:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
    end)
    trackedFrame:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, true)
        end
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    
    local trackedTitle = ns.FontManager:CreateFontString(trackedFrame, "header", "OVERLAY")
    trackedTitle:SetPoint("TOP", 0, -12)
    trackedTitle:SetText("|cff00ff00" .. ((ns.L and ns.L["TRACKED_LABEL"]) or "Tracked") .. "|r")
    
    local trackedDesc = ns.FontManager:CreateFontString(trackedFrame, "body", "OVERLAY")
    trackedDesc:SetPoint("TOP", trackedTitle, "BOTTOM", 0, -5)
    trackedDesc:SetWidth(185)
    trackedDesc:SetJustifyH("CENTER")
    trackedDesc:SetText("|cff88ff88" .. ((ns.L and ns.L["TRACKED_DETAILED_LINE1"]) or "Full detailed data") .. "|r\n|cffffffff" .. ((ns.L and ns.L["TRACKED_DETAILED_LINE2"]) or "All features enabled") .. "|r")
    
    -- Untracked option (RIGHT) - now a BUTTON
    local untrackedFrame = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    untrackedFrame:SetSize(200, 75)  -- Compact size
    untrackedFrame:SetPoint("TOP", charNameText, "BOTTOM", 110, optionsY)
    untrackedFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    untrackedFrame:SetBackdropColor(0.3, 0.1, 0.1, 1)
    untrackedFrame:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    
    -- Hover effect for Untracked card
    untrackedFrame:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.4, 0.15, 0.15, 1)  -- Brighter on hover
        self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
    end)
    untrackedFrame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.1, 0.1, 1)
        self:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    end)
    untrackedFrame:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
        end
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    
    local untrackedTitle = ns.FontManager:CreateFontString(untrackedFrame, "header", "OVERLAY")
    untrackedTitle:SetPoint("TOP", 0, -12)
    untrackedTitle:SetText("|cffff4444" .. ((ns.L and ns.L["UNTRACKED_LABEL"]) or "Untracked") .. "|r")
    
    local untrackedDesc = ns.FontManager:CreateFontString(untrackedFrame, "body", "OVERLAY")
    untrackedDesc:SetPoint("TOP", untrackedTitle, "BOTTOM", 0, -5)
    untrackedDesc:SetWidth(185)
    untrackedDesc:SetJustifyH("CENTER")
    untrackedDesc:SetText("|cffff8888" .. ((ns.L and ns.L["UNTRACKED_VIEWONLY_LINE1"]) or "View-only mode") .. "|r\n|cffffffff" .. ((ns.L and ns.L["UNTRACKED_VIEWONLY_LINE2"]) or "Basic info only") .. "|r")
    
    
    -- ESC-to-close (combat-safe: SetPropagateKeyboardInput is protected in 12.0)
    if not InCombatLockdown() then
        dialog:EnableKeyboard(true)
        dialog:SetPropagateKeyboardInput(true)
    end
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
            -- Treat ESC as "don't track" so state is consistent and user can enable later from Characters tab
            if ns.CharacterService then
                ns.CharacterService:ConfirmCharacterTracking(addon, charKey, false)
            end
            self:Hide()
        else
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end
    end)

    -- OnHide cleanup: clear addon reference so dialog can be shown again (e.g. next login or Track from Characters tab)
    dialog:SetScript("OnHide", function(self)
        self:SetScript("OnHide", nil)
        self:SetParent(nil)
        if addon then
            addon.trackingDialog = nil
        end
        _G["WarbandNexusTrackingDialog"] = nil
    end)
    
    -- Show dialog
    dialog:Show()
    
    -- Store reference to prevent garbage collection
    addon.trackingDialog = dialog
end

---Show tracking change confirmation (smaller popup for Enable/Disable from Characters tab)
---@param addon table The WarbandNexus addon instance
---@param charKey string Character key ("Name-Realm")
---@param charName string Character name (for display)
---@param enableTracking boolean True to enable, False to disable
function CharacterService:ShowTrackingChangeConfirmation(addon, charKey, charName, enableTracking)
    -- CRITICAL: If dialog already exists and is visible, don't create a new one
    if addon.trackingChangeDialog and addon.trackingChangeDialog:IsVisible() then
        return
    end
    
    -- Create confirmation dialog (standardized custom UI: ApplyVisuals + compact buttons, no icons)
    local ApplyVisuals = ns.UI_ApplyVisuals
    local UpdateBorderColor = ns.UI_UpdateBorderColor
    local COLORS = ns.UI_COLORS and ns.UI_COLORS.accent and ns.UI_COLORS or { accent = { 0.4, 0.2, 0.58 } }
    local accent = COLORS.accent
    
    local dialog = CreateFrame("Frame", "WarbandNexusTrackingChangeDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(320, 140)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(500)
    
    if ApplyVisuals then
        ApplyVisuals(dialog, { 0.05, 0.05, 0.07, 1 }, { accent[1], accent[2], accent[3], 0.9 })
    else
        dialog:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        dialog:SetBackdropColor(0.05, 0.05, 0.07, 1)
        dialog:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    end
    
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    
    -- Close button (standardized: small, accent border, X icon)
    local closeBtn = CreateFrame("Button", nil, dialog)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    if ApplyVisuals then
        ApplyVisuals(closeBtn, { 0.15, 0.15, 0.15, 0.9 }, { accent[1], accent[2], accent[3], 0.8 })
    end
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(12, 12)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    closeBtn:SetScript("OnClick", function()
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    closeBtn:SetScript("OnEnter", function(self)
        if closeIcon then closeIcon:SetVertexColor(1, 0.2, 0.2) end
    end)
    closeBtn:SetScript("OnLeave", function(self)
        if closeIcon then closeIcon:SetVertexColor(0.9, 0.3, 0.3) end
    end)
    
    -- Title
    local titleText = ns.FontManager:CreateFontString(dialog, "header", "OVERLAY")
    titleText:SetPoint("TOP", 0, -16)
    titleText:SetText("|cff9370DB" .. ((ns.L and ns.L["CONFIRM_ACTION"]) or "Confirm Action") .. "|r")
    
    -- Question text
    local questionText = ns.FontManager:CreateFontString(dialog, "body", "OVERLAY")
    questionText:SetPoint("TOP", titleText, "BOTTOM", 0, -10)
    questionText:SetWidth(320)
    questionText:SetJustifyH("CENTER")
    if enableTracking then
        questionText:SetText(string.format((ns.L and ns.L["ENABLE_TRACKING_FORMAT"]) or "Enable tracking for |cffffcc00%s|r?", charName))
    else
        questionText:SetText(string.format((ns.L and ns.L["DISABLE_TRACKING_FORMAT"]) or "Disable tracking for |cffffcc00%s|r?", charName))
    end
    
    -- Compact buttons (no icons): Confirm (green), Cancel (red)
    -- Anchored to dialog BOTTOM for symmetric positioning regardless of content
    local btnW, btnH, btnMarginBottom, gap = 100, 28, 16, 16
    
    -- Confirm (left) - anchored to dialog bottom-left area
    local yesCard = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    yesCard:SetSize(btnW, btnH)
    yesCard:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -(gap / 2), btnMarginBottom)
    if ApplyVisuals then
        ApplyVisuals(yesCard, { 0.1, 0.28, 0.18, 1 }, { 0.25, 0.65, 0.35, 1 })
    else
        yesCard:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
        yesCard:SetBackdropColor(0.1, 0.3, 0.2, 1)
        yesCard:SetBackdropBorderColor(0.2, 0.6, 0.3, 1)
    end
    yesCard:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.14, 0.35, 0.22, 1) end
        if UpdateBorderColor then UpdateBorderColor(self, { 0.35, 0.8, 0.45, 1 }) end
    end)
    yesCard:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.1, 0.28, 0.18, 1) end
        if UpdateBorderColor then UpdateBorderColor(self, { 0.25, 0.65, 0.35, 1 }) end
    end)
    yesCard:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if ns.CharacterService then
            ns.CharacterService:ConfirmCharacterTracking(addon, charKey, enableTracking)
        end
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    local yesText = ns.FontManager:CreateFontString(yesCard, "body", "OVERLAY")
    yesText:SetPoint("CENTER")
    yesText:SetText("|cff90ff90" .. ((ns.L and ns.L["CONFIRM"]) or "Confirm") .. "|r")
    
    -- Cancel (right) - anchored to dialog bottom-right area
    local noCard = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    noCard:SetSize(btnW, btnH)
    noCard:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", (gap / 2), btnMarginBottom)
    if ApplyVisuals then
        ApplyVisuals(noCard, { 0.28, 0.1, 0.1, 1 }, { 0.75, 0.22, 0.22, 1 })
    else
        noCard:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
        noCard:SetBackdropColor(0.3, 0.1, 0.1, 1)
        noCard:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    end
    noCard:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.38, 0.14, 0.14, 1) end
        if UpdateBorderColor then UpdateBorderColor(self, { 1, 0.3, 0.3, 1 }) end
    end)
    noCard:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(0.28, 0.1, 0.1, 1) end
        if UpdateBorderColor then UpdateBorderColor(self, { 0.75, 0.22, 0.22, 1 }) end
    end)
    noCard:SetScript("OnClick", function()
        dialog:Hide()
        dialog:SetParent(nil)
    end)
    local noText = ns.FontManager:CreateFontString(noCard, "body", "OVERLAY")
    noText:SetPoint("CENTER")
    noText:SetText("|cffff8080" .. (CANCEL or "Cancel") .. "|r")
    
    -- ESC-to-close (combat-safe: SetPropagateKeyboardInput is protected in 12.0)
    if not InCombatLockdown() then
        dialog:EnableKeyboard(true)
        dialog:SetPropagateKeyboardInput(true)
    end
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
            self:Hide()
        else
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        end
    end)

    -- OnHide cleanup
    dialog:SetScript("OnHide", function(self)
        self:SetScript("OnHide", nil)
        self:SetParent(nil)
        _G["WarbandNexusTrackingChangeDialog"] = nil
    end)
    
    -- Show dialog
    dialog:Show()
    
    -- Store reference
    addon.trackingChangeDialog = dialog
end

--============================================================================
-- FAVORITE CHARACTERS
--============================================================================

---Check if a character is marked as favorite
---@param addon table The WarbandNexus addon instance
---@param characterKey string Character key ("Name-Realm")
---@return boolean Whether the character is a favorite
function CharacterService:IsFavoriteCharacter(addon, characterKey)
    if not addon.db or not addon.db.global or not addon.db.global.favoriteCharacters then
        return false
    end
    
    local favs = addon.db.global.favoriteCharacters
    for fi = 1, #favs do
        local favKey = favs[fi]
        if favKey == characterKey then
            return true
        end
    end
    
    return false
end

---Build a set of favorite keys for O(1) lookups during roster paint (raw + canonical aliases).
---@param addon table WarbandNexus
---@return table<string, boolean>
function CharacterService:BuildFavoriteKeySet(addon)
    local set = {}
    if not addon or not addon.db or not addon.db.global or not addon.db.global.favoriteCharacters then
        return set
    end
    local favs = addon.db.global.favoriteCharacters
    local GetCanon = ns.Utilities and ns.Utilities.GetCanonicalCharacterKey
    for fi = 1, #favs do
        local k = favs[fi]
        if k and k ~= "" then
            set[k] = true
            if GetCanon then
                local c = ns.Utilities:GetCanonicalCharacterKey(k)
                if c and c ~= "" then
                    set[c] = true
                end
            end
        end
    end
    return set
end

---True if characterKey is favorite using a set from BuildFavoriteKeySet (matches alias normalization).
---@param favoriteSet table<string, boolean>|nil
---@param characterKey string|nil
---@return boolean
function CharacterService:IsFavoriteFromKeySet(favoriteSet, characterKey)
    if not favoriteSet or not characterKey or characterKey == "" then
        return false
    end
    if favoriteSet[characterKey] then
        return true
    end
    local GetCanon = ns.Utilities and ns.Utilities.GetCanonicalCharacterKey
    if GetCanon then
        local c = ns.Utilities:GetCanonicalCharacterKey(characterKey)
        if c and favoriteSet[c] then
            return true
        end
    end
    return false
end

---Toggle favorite status for a character
---@param addon table The WarbandNexus addon instance
---@param characterKey string Character key ("Name-Realm")
---@return boolean New favorite status
function CharacterService:ToggleFavoriteCharacter(addon, characterKey)
    if not addon.db or not addon.db.global then
        return false
    end
    
    -- Initialize if needed
    if not addon.db.global.favoriteCharacters then
        addon.db.global.favoriteCharacters = {}
    end
    
    local favorites = addon.db.global.favoriteCharacters
    local isFavorite = self:IsFavoriteCharacter(addon, characterKey)
    
    if isFavorite then
        -- Remove from favorites
        for i = 1, #favorites do
            local favKey = favorites[i]
            if favKey == characterKey then
                table.remove(favorites, i)
                addon:Print("|cffffff00" .. ((ns.L and ns.L["REMOVED_FROM_FAVORITES"]) or "Removed from favorites:") .. "|r " .. characterKey)
                if addon.SendMessage then
                    addon:SendMessage(E.CHARACTER_UPDATED, { charKey = characterKey, dataType = "favorite" })
                end
                break
            end
        end
        return false
    else
        -- Add to favorites
        table.insert(favorites, characterKey)
        if addon.db and addon.db.profile and addon.db.profile.characterGroupAssignments then
            ClearBothAssignKeys(addon.db.profile.characterGroupAssignments, characterKey)
        end
        addon:Print("|cffffd700" .. ((ns.L and ns.L["ADDED_TO_FAVORITES"]) or "Added to favorites:") .. "|r " .. characterKey)
        if addon.SendMessage then
            addon:SendMessage(E.CHARACTER_UPDATED, { charKey = characterKey, dataType = "favorite" })
        end
        return true
    end
end

--============================================================================
-- CUSTOM CHARACTER SECTIONS (profile: user-defined headers / buckets)
-- Tracked, non-favorite characters may be assigned to one custom section.
-- Favorites always render in the Favorites block; assignments for favorited keys are ignored.
--============================================================================

local CUSTOM_GROUP_LIST_KEY_PREFIX = "group_"

function CharacterService:GetCustomGroupListKey(groupId)
    if not groupId or groupId == "" then return nil end
    return CUSTOM_GROUP_LIST_KEY_PREFIX .. tostring(groupId)
end

function CharacterService:ParseCustomGroupIdFromListKey(listKey)
    if type(listKey) ~= "string" then return nil end
    if listKey:sub(1, #CUSTOM_GROUP_LIST_KEY_PREFIX) ~= CUSTOM_GROUP_LIST_KEY_PREFIX then return nil end
    return listKey:sub(#CUSTOM_GROUP_LIST_KEY_PREFIX + 1)
end

function CharacterService:EnsureCustomCharacterSectionsProfile(profile)
    if not profile then return end
    if type(profile.characterCustomGroups) ~= "table" then
        profile.characterCustomGroups = {}
    end
    if type(profile.characterGroupAssignments) ~= "table" then
        profile.characterGroupAssignments = {}
    end
    if type(profile.characterGroupExpanded) ~= "table" then
        profile.characterGroupExpanded = {}
    end
    if type(profile.characterSectionFilter) ~= "table" then
        profile.characterSectionFilter = { sectionKey = "all" }
    end
    if profile.characterSectionFilter.sectionKey == nil or profile.characterSectionFilter.sectionKey == "" then
        profile.characterSectionFilter.sectionKey = "all"
    end
    -- Gold-style highlights for any number of custom headers: set[groupId] = true
    if type(profile.characterFavoriteCustomGroupIds) ~= "table" then
        profile.characterFavoriteCustomGroupIds = {}
    end
    local legacy = profile.characterFavoriteCustomGroupId
    if legacy and legacy ~= "" and not profile.characterFavoriteCustomGroupIds[legacy] then
        profile.characterFavoriteCustomGroupIds[legacy] = true
    end
    profile.characterFavoriteCustomGroupId = nil
    local groups = profile.characterCustomGroups or {}
    local valid = {}
    for i = 1, #groups do
        local gid = groups[i].id
        if gid then valid[gid] = true end
    end
    for gid, _ in pairs(profile.characterFavoriteCustomGroupIds) do
        if not valid[gid] then
            profile.characterFavoriteCustomGroupIds[gid] = nil
        end
    end
end

--- Whether a custom section uses the gold header preset (Characters / Professions).
function CharacterService:IsProfileCustomSectionHighlighted(profile, groupId)
    if not profile or not groupId or groupId == "" then return false end
    if type(profile.characterFavoriteCustomGroupIds) == "table" and profile.characterFavoriteCustomGroupIds[groupId] then
        return true
    end
    return profile.characterFavoriteCustomGroupId == groupId
end

--- Toggle gold highlight for one custom section. Returns new highlighted state, or nil if groupId is invalid.
function CharacterService:ToggleFavoriteCustomHeaderHighlight(addon, groupId)
    if not addon or not addon.db or not addon.db.profile or not groupId or groupId == "" then return nil end
    local profile = addon.db.profile
    self:EnsureCustomCharacterSectionsProfile(profile)
    local groups = profile.characterCustomGroups or {}
    local found = false
    for i = 1, #groups do
        if groups[i].id == groupId then found = true break end
    end
    if not found then return nil end
    local set = profile.characterFavoriteCustomGroupIds
    local now = not (set[groupId] and true or false)
    if now then
        set[groupId] = true
    else
        set[groupId] = nil
    end
    profile.characterFavoriteCustomGroupId = nil
    if addon.SendMessage then
        addon:SendMessage(E.CHARACTER_UPDATED, { charKey = nil, dataType = "customSections" })
    end
    return now
end

--- Clear all gold highlights, or toggle one section (compat: non-nil groupId calls toggle).
function CharacterService:SetFavoriteCustomSectionGroupId(addon, groupId)
    if not addon or not addon.db or not addon.db.profile then return false end
    local profile = addon.db.profile
    self:EnsureCustomCharacterSectionsProfile(profile)
    if groupId == nil or groupId == "" then
        wipe(profile.characterFavoriteCustomGroupIds)
        profile.characterFavoriteCustomGroupId = nil
        if addon.SendMessage then
            addon:SendMessage(E.CHARACTER_UPDATED, { charKey = nil, dataType = "customSections" })
        end
        return true
    end
    return self:ToggleFavoriteCustomHeaderHighlight(addon, groupId) ~= nil
end

--- Ordered custom groups: highlighted sections first, then others. Within each bucket: manual = profile array order, else alphabetical by display name.
function CharacterService:BuildOrderedCustomCharacterGroups(profile, sortKey)
    if not profile then return {} end
    self:EnsureCustomCharacterSectionsProfile(profile)
    local raw = profile.characterCustomGroups or {}
    if #raw == 0 then return raw end
    sortKey = (type(sortKey) == "string" and sortKey ~= "") and sortKey or "default"
    local decorated = {}
    for i = 1, #raw do
        decorated[#decorated + 1] = { g = raw[i], idx = i }
    end
    local function labelLower(g)
        local n = g and (g.name or g.id)
        if not n or (issecretvalue and issecretvalue(n)) then return "" end
        return string.lower(tostring(n))
    end
    table.sort(decorated, function(a, b)
        local fa = self:IsProfileCustomSectionHighlighted(profile, a.g.id)
        local fb = self:IsProfileCustomSectionHighlighted(profile, b.g.id)
        if fa ~= fb then
            return fa
        end
        if sortKey == "manual" then
            return a.idx < b.idx
        end
        local la, lb = labelLower(a.g), labelLower(b.g)
        if la ~= lb then
            return la < lb
        end
        return tostring(a.g.id) < tostring(b.g.id)
    end)
    local out = {}
    for i = 1, #decorated do
        out[i] = decorated[i].g
    end
    return out
end

function CharacterService:GenerateCustomGroupId(profile)
    self:EnsureCustomCharacterSectionsProfile(profile)
    local n = tonumber(profile._characterCustomGroupSeq) or 0
    n = n + 1
    profile._characterCustomGroupSeq = n
    return "cgh" .. tostring(n)
end

function CharacterService:AddCustomCharacterSection(addon, displayName)
    if not addon or not addon.db or not addon.db.profile then return nil end
    local profile = addon.db.profile
    self:EnsureCustomCharacterSectionsProfile(profile)
    local name = displayName
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$") or ""
    if name == "" or (issecretvalue and issecretvalue(name)) then return nil end
    local id = self:GenerateCustomGroupId(profile)
    profile.characterCustomGroups[#profile.characterCustomGroups + 1] = { id = id, name = name }
    local lk = self:GetCustomGroupListKey(id)
    if lk and not profile.characterOrder then
        profile.characterOrder = { favorites = {}, regular = {}, untracked = {} }
    end
    if lk and profile.characterOrder and not profile.characterOrder[lk] then
        profile.characterOrder[lk] = {}
    end
    if addon.SendMessage then
        addon:SendMessage(E.CHARACTER_UPDATED, { charKey = nil, dataType = "customSections" })
    end
    return id
end

function CharacterService:RenameCustomCharacterSection(addon, groupId, displayName)
    if not addon or not addon.db or not addon.db.profile or not groupId then return false end
    local profile = addon.db.profile
    self:EnsureCustomCharacterSectionsProfile(profile)
    local name = displayName
    if type(name) ~= "string" then return false end
    name = name:match("^%s*(.-)%s*$") or ""
    if name == "" or (issecretvalue and issecretvalue(name)) then return false end
    local groups = profile.characterCustomGroups
    for i = 1, #groups do
        if groups[i].id == groupId then
            groups[i].name = name
            if addon.SendMessage then
                addon:SendMessage(E.CHARACTER_UPDATED, { charKey = nil, dataType = "customSections" })
            end
            return true
        end
    end
    return false
end

function CharacterService:RemoveCustomCharacterSection(addon, groupId)
    if not addon or not addon.db or not addon.db.profile or not groupId then return false end
    local profile = addon.db.profile
    self:EnsureCustomCharacterSectionsProfile(profile)
    local groups = profile.characterCustomGroups
    local lk = self:GetCustomGroupListKey(groupId)
    for i = #groups, 1, -1 do
        if groups[i].id == groupId then
            tremove(groups, i)
            break
        end
    end
    local assign = profile.characterGroupAssignments
    if assign then
        for k, gid in pairs(assign) do
            if gid == groupId then
                assign[k] = nil
            end
        end
    end
    profile.characterGroupExpanded[groupId] = nil
    if profile.characterFavoriteCustomGroupIds then
        profile.characterFavoriteCustomGroupIds[groupId] = nil
    end
    if profile.characterFavoriteCustomGroupId == groupId then
        profile.characterFavoriteCustomGroupId = nil
    end
    if profile.characterOrder and lk then
        profile.characterOrder[lk] = nil
    end
    local sf = profile.characterSectionFilter
    if sf and sf.sectionKey == lk then
        sf.sectionKey = "all"
    end
    local psf = profile.professionSectionFilter
    if psf and psf.sectionKey == lk then
        psf.sectionKey = "all"
    end
    local pveSf = profile.pveSectionFilter
    if pveSf and pveSf.sectionKey == lk then
        pveSf.sectionKey = "all"
    end
    if addon.SendMessage then
        addon:SendMessage(E.CHARACTER_UPDATED, { charKey = nil, dataType = "customSections" })
    end
    return true
end

--- Assign a tracked non-favorite character to a custom section (groupId nil = ungrouped / main list).
function CharacterService:SetCharacterCustomSection(addon, charKey, groupId)
    if not addon or not addon.db or not addon.db.profile or not charKey or charKey == "" then return false end
    local profile = addon.db.profile
    self:EnsureCustomCharacterSectionsProfile(profile)
    if ns.CharacterService:IsFavoriteCharacter(addon, charKey) then
        return false
    end
    local assign = profile.characterGroupAssignments
    local storeKey = AssignKeyFromCharKey(charKey)
    if not storeKey then return false end
    if groupId and groupId ~= "" then
        local found = false
        local groups = profile.characterCustomGroups
        for i = 1, #groups do
            if groups[i].id == groupId then found = true break end
        end
        if not found then return false end
        assign[storeKey] = groupId
        if charKey ~= storeKey then
            assign[charKey] = nil
        end
    else
        ClearBothAssignKeys(assign, charKey)
    end
    if addon.SendMessage then
        addon:SendMessage(E.CHARACTER_UPDATED, { charKey = storeKey, dataType = "customSection" })
    end
    return true
end

function CharacterService:GetCharacterCustomSectionId(addon, charKey)
    if not addon or not addon.db or not addon.db.profile or not charKey then return nil end
    local profile = addon.db.profile
    self:EnsureCustomCharacterSectionsProfile(profile)
    local assign = profile.characterGroupAssignments
    if not assign then return nil end
    local storeKey = AssignKeyFromCharKey(charKey)
    local gid = assign[storeKey]
    if gid then return gid end
    return assign[charKey]
end

--============================================================================
-- EXPORT
--============================================================================

return CharacterService
