--[[
    Warband Nexus - Character Service
    Manages character tracking, favorites, and character-specific operations
    Extracted from Core.lua for proper separation of concerns

    Tracking dialogs: Modules/UI/CharacterTrackingDialog.lua (view layer).
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

-- CHARACTER TRACKING

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

    local chars = addon.db.global.characters
    local persistKey = self:GetCharactersTablePersistKey(addon, charKey) or charKey
    if not persistKey then return end

    -- Collapse legacy Name-Realm slot into GUID (or other canonical) slot without dropping fields.
    if persistKey ~= charKey and chars[charKey] and not chars[persistKey] then
        chars[persistKey] = chars[charKey]
        chars[charKey] = nil
    elseif persistKey ~= charKey and chars[charKey] and chars[persistKey] then
        local src, dst = chars[charKey], chars[persistKey]
        for k, v in pairs(src) do
            if dst[k] == nil then dst[k] = v end
        end
        chars[charKey] = nil
    end

    if not chars[persistKey] then
        chars[persistKey] = {}
    end
    local entry = chars[persistKey]
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

    -- Player GUID: capture only when user opts into tracking (avoid UnitGUID on every minimal save / tab draw).
    if isTracked then
        if ns.Utilities and ns.Utilities.SafeGuid then
            local g = ns.Utilities:SafeGuid("player")
            if type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g)) then
                entry.guid = g
            end
        end
    else
        entry.guid = nil
    end
    
    -- HYBRID: Broadcast event for modules to react (event-driven component)
    addon:SendMessage(E.CHARACTER_TRACKING_CHANGED, {
        charKey = persistKey,
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
        
        -- Reset characterSaved flag (in case of DB wipe without reload)
        addon.characterSaved = false

        -- Ensure combat-safety frame exists before any SafeInit (tracking dialog can confirm before init drain).
        local InitSvc = ns.InitializationService
        if InitSvc and InitSvc.SetupCombatSafety then
            InitSvc:SetupCombatSafety()
        end
        local SafeInit = InitSvc and InitSvc.SafeInit
        
        -- Register event listeners + character cache (skipped during init)
        -- Wrapped in SafeInit: user may confirm tracking while in combat
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
        
        -- Initial character data save (basic info)
        C_Timer.After(0.1, function()
            local function step2()
                local addonInstance = _G.WarbandNexus or addon
                if addonInstance and addonInstance.SaveCharacter then
                    addonInstance:SaveCharacter()
                end
            end
            if SafeInit then SafeInit(step2, "PostConfirm:SaveCharacterInitial") else step2() end
        end)
        
        -- Trigger items scan (fixes ItemsUI empty on first tracking)
        C_Timer.After(0.2, function()
            local function step3()
                local addonInstance = _G.WarbandNexus or addon
                if addonInstance and addonInstance.ScanInventoryBags then
                    local cKey = ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey
                        and ns.CharacterService:ResolveCharactersTableKey(addonInstance)
                    if not cKey and ns.Utilities.GetCharacterStorageKey then
                        cKey = ns.Utilities:GetCharacterStorageKey(addonInstance)
                    end
                    if not cKey and ns.Utilities.GetCharacterStorageKey then
                        cKey = ns.Utilities:GetCharacterStorageKey(addonInstance)
                    end
                    addonInstance:ScanInventoryBags(cKey)
                    if ns.ItemsLoadingState then
                        ns.ItemsLoadingState.isLoading = false
                        ns.ItemsLoadingState.scanProgress = 100
                        ns.ItemsLoadingState.loadingProgress = 100
                        ns.ItemsLoadingState.currentStage = nil
                    end
                end
            end
            if SafeInit then SafeInit(step3, "PostConfirm:ScanInventoryBags") else step3() end
        end)
        
        -- Trigger reputation scan
        C_Timer.After(1, function()
            local function step4()
                local addonInstance = _G.WarbandNexus or addon
                if addonInstance and addonInstance.ScanReputations then
                    addonInstance:ScanReputations()
                end
                -- LT:Complete("reputations") called by PerformFullScan when done
            end
            if SafeInit then SafeInit(step4, "PostConfirm:ScanReputations") else step4() end
        end)
        
        -- Trigger currency scan
        C_Timer.After(1.5, function()
            local function step5()
                if ns.CurrencyCache and ns.CurrencyCache.PerformFullScan then
                    ns.CurrencyCache:PerformFullScan(true)
                end
            end
            if SafeInit then SafeInit(step5, "PostConfirm:CurrencyPerformFullScan") else step5() end
        end)
        
        -- Force item level update
        C_Timer.After(1.2, function()
            local function step6()
                local addonInstance = _G.WarbandNexus or addon
                if addonInstance and addonInstance.UpdateCharacterCache then
                    addonInstance:UpdateCharacterCache("itemLevel")
                end
            end
            if SafeInit then SafeInit(step6, "PostConfirm:UpdateCharacterCacheIlvl") else step6() end
        end)
        
        -- Re-save character data (ensures all data is fresh)
        C_Timer.After(1.8, function()
            local function step7()
                local addonInstance = _G.WarbandNexus or addon
                if addonInstance then
                    addonInstance.characterSaved = false
                    if addonInstance.SaveCharacter then
                        addonInstance:SaveCharacter()
                    end
                end
                local LT = ns.LoadingTracker
                if LT then LT:Complete("character") end
            end
            if SafeInit then SafeInit(step7, "PostConfirm:SaveCharacterFinal") else step7() end
        end)
        
        -- Notify UI to refresh (event-driven; UI listens for WN_CHARACTER_UPDATED)
        C_Timer.After(2.2, function()
            local function doStep8()
                local addonInstance = _G.WarbandNexus or addon
                if addonInstance and addonInstance.SendMessage then
                    local ev = E.CHARACTER_UPDATED
                    local msgKey = persistKey or charKey
                    addonInstance:SendMessage(ev, { charKey = msgKey })
                end
            end
            if SafeInit then SafeInit(doStep8, "PostConfirm:UIRefresh") else doStep8() end
        end)
        
        -- Profession data collection
        -- Core.lua timers (T+4-5s from login) may have already fired before user confirmed.
        -- These functions are safe to call multiple times (idempotent overwrites).
        C_Timer.After(3, function()
            local function step9()
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
            end
            if SafeInit then SafeInit(step9, "PostConfirm:ProfessionsCollectLogin") else step9() end
        end)
        C_Timer.After(4, function()
            local function step9b()
                local addonInstance = _G.WarbandNexus or addon
                if addonInstance and addonInstance._coreStartupPhasesPending then
                    return
                end
                if addonInstance and addonInstance.CollectExpansionProfessionsOnLogin then
                    addonInstance:CollectExpansionProfessionsOnLogin()
                end
                local LT = ns.LoadingTracker
                if LT then LT:Complete("professions") end
            end
            if SafeInit then SafeInit(step9b, "PostConfirm:ProfessionsExpansion") else step9b() end
        end)
        
        -- PvE data + Knowledge collection
        C_Timer.After(4.5, function()
            local function step10()
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
            end
            if SafeInit then SafeInit(step10, "PostConfirm:PvEAndKnowledge") else step10() end
        end)
        
        -- Played time + profession recharge timer
        -- These were gated on tracking in Core.lua/EventManager.lua
        C_Timer.After(2, function()
            local function step11()
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
            end
            if SafeInit then SafeInit(step11, "PostConfirm:PlayedTimeRecharge") else step11() end
        end)
        
        -- What's New notification
        C_Timer.After(0.5, function()
            local function step12()
                local addonInstance = _G.WarbandNexus or addon
                if addonInstance and addonInstance.CheckNotificationsOnLogin then
                    addonInstance:CheckNotificationsOnLogin()
                end
            end
            if SafeInit then SafeInit(step12, "PostConfirm:WhatsNew") else step12() end
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
                    local msgKey = ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(addonInstance)
                    if msgKey and ns.Utilities.GetCanonicalCharacterKey then
                        msgKey = ns.Utilities:GetCanonicalCharacterKey(msgKey) or msgKey
                    end
                    addonInstance:SendMessage(ev, { charKey = msgKey })
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
    local U = ns.Utilities
    -- Canonical slot for current session (guid when available — matches NEW writes / migrated rows).
    local storageKey = U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(addon)
    if storageKey and storageKey ~= "" and chars[storageKey] then
        return storageKey
    end
    local rawKey = U and U.GetCharacterKey and U:GetCharacterKey()
    if not rawKey or rawKey == "" then
        return nil
    end
    if chars[rawKey] then
        return rawKey
    end
    if U and U.GetCanonicalCharacterKey then
        local canon = U:GetCanonicalCharacterKey(rawKey)
        if canon and canon ~= "" and canon ~= rawKey and chars[canon] then
            return canon
        end
    end
    -- Stale row key after a rename: same player GUID under a legacy table key.
    if U and U.SafeGuid then
        local pg = U:SafeGuid("player")
        if pg and not (issecretvalue and issecretvalue(pg)) then
            local bestKey, bestSeen = nil, -1
            for k, v in pairs(chars) do
                if type(v) == "table" then
                    local g = v.guid
                    if type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g)) and g == pg then
                        local seen = (type(v.lastSeen) == "number") and v.lastSeen or 0
                        if seen > bestSeen then
                            bestSeen = seen
                            bestKey = k
                        end
                    end
                end
            end
            if bestKey then
                return bestKey
            end
        end
    end
    return nil
end

--- True when `subsidiaryKey` belongs to a row in `db.global.characters` (GUID vs Name-Realm index safe).
--- Used by orphan cleanup so per-character currency/PvE buckets are not deleted after GUID migration.
--- @param addon table WarbandNexus
--- @param subsidiaryKey string Storage key from currencyData / pveCache / etc.
--- @return boolean
function CharacterService:CharacterOwnsSubsidiaryKey(addon, subsidiaryKey)
    if not subsidiaryKey or subsidiaryKey == "" then return false end
    if issecretvalue and issecretvalue(subsidiaryKey) then return false end
    if not addon or not addon.db or not addon.db.global then return false end
    local chars = addon.db.global.characters
    if type(chars) ~= "table" then return false end

    if chars[subsidiaryKey] then return true end

    local U = ns.Utilities
    local canon = U and U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(subsidiaryKey) or subsidiaryKey
    if canon and canon ~= "" and chars[canon] then return true end

    for key, row in pairs(chars) do
        if type(row) == "table" then
            if key == subsidiaryKey or (canon and key == canon) then return true end
            if U and U.ResolveCharacterRowKey then
                local rowKey = U:ResolveCharacterRowKey(row)
                if rowKey == subsidiaryKey or (canon and rowKey == canon) then return true end
            end
            if not (U and U.IsGuidOnlySubsidiaryReads and U:IsGuidOnlySubsidiaryReads(addon.db)) then
                if ns.VaultCharKeysMatch and (ns.VaultCharKeysMatch(key, subsidiaryKey) or (canon and ns.VaultCharKeysMatch(key, canon))) then
                    return true
                end
            end
        end
    end
    return false
end

--- Remove all matching keys (exact + alias) from a char-keyed subsidiary table.
---@param tbl table|nil
---@param charKey string
---@return number removed
local function PurgeCharKeyedEntries(tbl, charKey)
    if type(tbl) ~= "table" or not charKey or charKey == "" then return 0 end
    local removed = 0
    local toNil = {}
    for k in pairs(tbl) do
        if k == charKey or (ns.VaultCharKeysMatch and ns.VaultCharKeysMatch(k, charKey)) then
            toNil[#toNil + 1] = k
        end
    end
    for i = 1, #toNil do
        tbl[toNil[i]] = nil
        removed = removed + 1
    end
    return removed
end

--- Drop per-character subsidiary storage when a roster row is deleted or pruned by limit enforcement.
---@param addon table WarbandNexus
---@param charKey string
---@return number removed Key buckets cleared
function CharacterService:RemoveCharacterSubsidiaryKeys(addon, charKey)
    if not addon or not addon.db or not addon.db.global or not charKey or charKey == "" then
        return 0
    end
    local g = addon.db.global
    local removed = 0

    local cd = g.currencyData
    if cd then
        if cd.currencies then removed = removed + PurgeCharKeyedEntries(cd.currencies, charKey) end
        if cd.totalEarned then removed = removed + PurgeCharKeyedEntries(cd.totalEarned, charKey) end
    end

    removed = removed + PurgeCharKeyedEntries(g.gearData, charKey)
    removed = removed + PurgeCharKeyedEntries(g.pveProgress, charKey)
    removed = removed + PurgeCharKeyedEntries(g.statisticSnapshots, charKey)
    removed = removed + PurgeCharKeyedEntries(g.personalBanks, charKey)
    removed = removed + PurgeCharKeyedEntries(g.itemStorage, charKey)

    local pc = g.pveCache
    if type(pc) == "table" then
        local mp = pc.mythicPlus
        if mp then
            removed = removed + PurgeCharKeyedEntries(mp.keystones, charKey)
            removed = removed + PurgeCharKeyedEntries(mp.bestRuns, charKey)
            removed = removed + PurgeCharKeyedEntries(mp.dungeonScores, charKey)
            removed = removed + PurgeCharKeyedEntries(mp.runHistory, charKey)
        end
        local gv = pc.greatVault
        if gv then
            removed = removed + PurgeCharKeyedEntries(gv.activities, charKey)
            removed = removed + PurgeCharKeyedEntries(gv.rewards, charKey)
        end
        local lo = pc.lockouts
        if lo then
            removed = removed + PurgeCharKeyedEntries(lo.raids, charKey)
            removed = removed + PurgeCharKeyedEntries(lo.dungeons, charKey)
            removed = removed + PurgeCharKeyedEntries(lo.worldBosses, charKey)
        end
        if pc.delves and pc.delves.characters then
            removed = removed + PurgeCharKeyedEntries(pc.delves.characters, charKey)
        end
    end

    for _, repData in pairs(g.reputations or {}) do
        if type(repData) == "table" and repData.chars then
            removed = removed + PurgeCharKeyedEntries(repData.chars, charKey)
        end
    end

    local rd = g.reputationData
    if rd and rd.characters then
        removed = removed + PurgeCharKeyedEntries(rd.characters, charKey)
    end

    if removed > 0 and DebugPrint then
        DebugPrint(string.format("|cffff8000[WN Char]|r Subsidiary purge %s: %d bucket(s)", tostring(charKey), removed))
    end
    return removed
end

--- Canonical key for subsidiary globals (`db.global.currencies`, etc.) — same namespace rules as `characters`.
--- @param addon table|nil WarbandNexus
--- @param optionalCharKey string|nil Explicit character (UI / roster); nil = logged-in player
--- @return string|nil
function CharacterService:ResolveSubsidiaryCharacterKey(addon, optionalCharKey)
    if optionalCharKey and optionalCharKey ~= "" then
        local U = ns.Utilities
        if U and U.GetCanonicalCharacterKey then
            return U:GetCanonicalCharacterKey(optionalCharKey) or optionalCharKey
        end
        return optionalCharKey
    end
    local r = addon and self:ResolveCharactersTableKey(addon)
    if r then return r end
    local U = ns.Utilities
    if U and U.GetCharacterStorageKey then
        local sk = addon and U:GetCharacterStorageKey(addon) or nil
        if sk and sk ~= "" then
            if U.GetCanonicalCharacterKey then
                return U:GetCanonicalCharacterKey(sk) or sk
            end
            return sk
        end
    end
    return addon and U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(addon) or nil
end

--- Table index for `db.global.characters` writes (tracking dialog, etc.): existing row, else GUID bucket for current player.
--- @param addon table WarbandNexus
--- @param incomingUIKey string|nil Selector from UI (often Name-Realm for self)
--- @return string|nil
function CharacterService:GetCharactersTablePersistKey(addon, incomingUIKey)
    local resolved = addon and self:ResolveCharactersTableKey(addon)
    if resolved then return resolved end
    local U = ns.Utilities
    if not U then return incomingUIKey end
    local legacy = U.GetCharacterKey and U:GetCharacterKey()
    local sk = addon and U.GetCharacterStorageKey and U:GetCharacterStorageKey(addon) or nil
    if incomingUIKey and legacy and incomingUIKey == legacy and sk and sk ~= "" then
        if U.GetCanonicalCharacterKey then
            return U:GetCanonicalCharacterKey(sk) or sk
        end
        return sk
    end
    if incomingUIKey and U.GetCanonicalCharacterKey then
        return U:GetCanonicalCharacterKey(incomingUIKey) or incomingUIKey
    end
    if sk and sk ~= "" and U.GetCanonicalCharacterKey then
        return U:GetCanonicalCharacterKey(sk) or sk
    end
    return incomingUIKey
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
    
    -- Explicit true check - only track if user explicitly enabled tracking
    -- nil or false = not tracked (requires user action to enable)
    return charData.isTracked == true
end

---Show character tracking confirmation dialog (delegates to CharacterTrackingDialog view).
---@param addon table The WarbandNexus addon instance
---@param charKey string Character key ("Name-Realm")
function CharacterService:ShowCharacterTrackingConfirmation(addon, charKey)
    local ev = E and E.CHARACTER_TRACKING_DIALOG_REQUESTED
    if ev and addon and addon.SendMessage then
        addon:SendMessage(ev, { mode = "initial", charKey = charKey })
        return
    end
    local D = ns.CharacterTrackingDialog
    if D and D.ShowInitial then
        D.ShowInitial(addon, charKey)
    end
end

---Show tracking change confirmation (delegates to CharacterTrackingDialog view).
---@param addon table The WarbandNexus addon instance
---@param charKey string Character key ("Name-Realm")
---@param charName string Character name (for display)
---@param enableTracking boolean True to enable, False to disable
function CharacterService:ShowTrackingChangeConfirmation(addon, charKey, charName, enableTracking)
    local ev = E and E.CHARACTER_TRACKING_DIALOG_REQUESTED
    if ev and addon and addon.SendMessage then
        addon:SendMessage(ev, {
            mode = "change",
            charKey = charKey,
            charName = charName,
            enableTracking = enableTracking == true,
        })
        return
    end
    local D = ns.CharacterTrackingDialog
    if D and D.ShowChange then
        D.ShowChange(addon, charKey, charName, enableTracking)
    end
end

---Other roster rows that share the logged-in character name but use a different storage key (realm transfer / faction copy leftovers).
---@param addon table WarbandNexus
---@return table[] copies { key, name, realm, lastSeen }
function CharacterService:FindProbableStaleCharacterCopies(addon)
    if not addon or not addon.db or not addon.db.global or not addon.db.global.characters then
        return {}
    end
    local U = ns.Utilities
    local currentKey = self:ResolveCharactersTableKey(addon)
    if not currentKey and U and U.GetCharacterStorageKey then
        currentKey = U:GetCharacterStorageKey(addon)
    end
    local playerName = UnitName("player")
    if not playerName or playerName == "" or (issecretvalue and issecretvalue(playerName)) then
        return {}
    end
    local nameLower = playerName:lower()
    local copies = {}
    local chars = addon.db.global.characters
    for key, row in pairs(chars) do
        if key ~= currentKey and type(row) == "table" then
            local n = row.name
            if type(n) == "string" and n ~= "" and not (issecretvalue and issecretvalue(n)) then
                if n:lower() == nameLower then
                    copies[#copies + 1] = {
                        key = key,
                        name = n,
                        realm = row.realm,
                        lastSeen = row.lastSeen,
                    }
                end
            end
        end
    end
    return copies
end

-- FAVORITE CHARACTERS

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

    local U = ns.Utilities
    if U and U.GetCanonicalCharacterKey and characterKey then
        characterKey = U:GetCanonicalCharacterKey(characterKey) or characterKey
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

-- CUSTOM CHARACTER SECTIONS (profile: user-defined headers / buckets)
-- Tracked, non-favorite characters may be assigned to one custom section.
-- Favorites always render in the Favorites block; assignments for favorited keys are ignored.

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

-- EXPORT

return CharacterService