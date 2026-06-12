--[[
    Warband Nexus - Main shell WN_* message listeners (PopulateContent coalescing).
    Split from Modules/UI.lua CreateMainWindow closure.
    Loaded from WarbandNexus.toc immediately before Modules/UI.lua.
]]

local _, ns = ...

ns.UI_RefreshRouter = ns.UI_RefreshRouter or {}

function ns.UI_RefreshRouter.RegisterMainShellListeners(ctx)
    if not ctx or not ctx.addon or not ctx.frame or not ctx.eventsSelf or not ctx.constants or not ctx.state then
        return
    end
    local WarbandNexus = ctx.addon
    local f = ctx.frame
    local UIEvents = ctx.eventsSelf
    local Constants = ctx.constants
    local st = ctx.state
    local SchedulePopulateContent = ctx.schedulePopulate
    local ScheduleGearTabInventoryNarrowRefresh = ctx.scheduleGearInvNarrow
    local ThrottledScheduleGearAsyncRepaint = ctx.throttledGearAsyncRepaint
    local IsGearTabPopulateQuiet = ctx.isGearTabQuiet
    local UpdateTabVisibility = ctx.updateTabVisibility
    local ScrollMainNavEnsureTabVisible = ctx.scrollNavEnsureTabVisible
    local UpdateTabButtonStates = ctx.updateTabButtonStates
    local GEAR_STORAGE_REC_REFRESH_DEBOUNCE = ctx.gearStorageRecRefreshDebounce or 0.06

    -- Data-change handlers below early-out while the shell is hidden. Record that an
    -- update arrived so the master OnShow hook (UI.lua CreateMainWindow) can repaint
    -- once on reopen; without this, events during combat-hide or a manual close leave
    -- stale tab content until the user switches tabs.
    local function HiddenOrMissing()
        if not f then return true end
        if not f:IsShown() then
            st.dirtyWhileHidden = true
            return true
        end
        return false
    end
    -- NOTE: All RegisterMessage calls use UIEvents as the 'self' key to avoid
    -- overwriting other modules' handlers for the same AceEvent message.
    -- AceEvent allows only ONE handler per (event, self) pair.
    -- Must bypass POPULATE_COOLDOWN: after login/alt switch, ITEMS_UPDATED etc. can set st.lastEventPopulateTime
    -- and this refresh would be dropped — leaving Character tab layout stale or visually broken.
    -- Gear tab rebuilds 3D paperdoll + full card — avoid skipCooldown (full populate every ~0.1s) on
    -- rapid WN_CHARACTER_UPDATED (e.g. item level ticks at 0.3s, DataService) or models appear to "flicker".
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CHARACTER_UPDATED, function(_, payload)
        if HiddenOrMissing() then return end
        local tab = f.currentTab
        if tab ~= "chars" and tab ~= "stats" and tab ~= "gear" then return end
        -- Characters tab: avoid skipCooldown here — ilvl/zone/gold batching fires this often and full
        -- PopulateContent every ~100ms feels like a constant refresh (virtual rows make it more noticeable).
        if tab == "chars" then
            SchedulePopulateContent()
        elseif tab == "stats" then
            SchedulePopulateContent(true)
        elseif tab == "gear" then
            if payload and payload.dataType == "itemLevel" and payload.charKey
                and WarbandNexus.TryRefreshGearTabItemLevelOnly
                and WarbandNexus:TryRefreshGearTabItemLevelOnly(payload.charKey) then
                return
            end
            if f._gearCharUpdSuppressUntil and GetTime() < f._gearCharUpdSuppressUntil then
                return
            end
            if IsGearTabPopulateQuiet() then
                return
            end
            SchedulePopulateContent()
        end
    end)
    
    local function onItemsOrBagsInventoryUpdated()
        if not HiddenOrMissing() and (f.currentTab == "items" or f.currentTab == "gear") then
            -- Bank > Warband aggregate can sit on this tab while cache finishes; 800ms POPULATE_COOLDOWN
            -- otherwise drops the follow-up populate and the list looks empty until a tab switch.
            if f.currentTab == "items" and ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() == "warband" then
                SchedulePopulateContent(true)
            elseif f.currentTab == "gear" then
                ScheduleGearTabInventoryNarrowRefresh()
            else
                SchedulePopulateContent()
            end
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.ITEMS_UPDATED, onItemsOrBagsInventoryUpdated)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.GEAR_UPDATED, function(_, payload)
        if not HiddenOrMissing() and f.currentTab == "gear" then
            local gearQuiet = IsGearTabPopulateQuiet()
            -- ScanEquippedGear always reports the logged-in character. If the Gear tab is showing
            -- another roster entry (offline alt), a full PopulateContent here only bumps drawGen,
            -- aborts in-flight storage Find, and leaves recommendations / loading veil stuck.
            local gearCanon = f._gearPopulateCanonKey
            if gearCanon and payload and payload.charKey then
                local U = ns.Utilities
                local pCanon = U and U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(payload.charKey) or payload.charKey
                local gCanon = U and U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(gearCanon) or gearCanon
                if pCanon and gCanon and pCanon ~= gCanon then
                    return
                end
            end
            local function runGearStorageRecRefreshNow()
                local equipOnly = st.gearStorageRecRefreshEquipOnly == true
                st.gearStorageRecRefreshEquipOnly = false
                st.gearStorageRecRefreshTimer = nil
                if HiddenOrMissing() or f.currentTab ~= "gear" then return end
                local gearCanon = f._gearPopulateCanonKey
                if not gearCanon then return end
                local gen = ns._gearTabDrawGen or 0
                if equipOnly then
                    if WarbandNexus.NotifyGearStorageEquipChanged then
                        WarbandNexus:NotifyGearStorageEquipChanged(gearCanon)
                    end
                    if WarbandNexus.IsGearStorageScanInFlightForCanon
                        and WarbandNexus:IsGearStorageScanInFlightForCanon(gearCanon) then
                        return
                    end
                    if WarbandNexus.TryRedrawGearStorageRecAfterEquipChange
                        and WarbandNexus:TryRedrawGearStorageRecAfterEquipChange(gearCanon, gen) then
                        return
                    end
                end
                if WarbandNexus.InvalidateGearStorageFindingsCacheForCanon then
                    WarbandNexus:InvalidateGearStorageFindingsCacheForCanon(gearCanon)
                end
                if WarbandNexus.IsGearStorageScanInFlightForCanon
                    and WarbandNexus:IsGearStorageScanInFlightForCanon(gearCanon) then
                    return
                end
                if WarbandNexus.ScheduleGearStorageFindingsResolve then
                    WarbandNexus:ScheduleGearStorageFindingsResolve(gearCanon, gen, function()
                        C_Timer.After(0, function()
                            if HiddenOrMissing() or f.currentTab ~= "gear" then return end
                            if WarbandNexus.RedrawGearStorageRecommendationsOnly then
                                ns._gearStorageAllowEquipSigInvBypass = true
                                WarbandNexus:RedrawGearStorageRecommendationsOnly(gearCanon, ns._gearTabDrawGen or 0, true)
                                ns._gearStorageAllowEquipSigInvBypass = false
                            end
                        end)
                    end)
                elseif WarbandNexus.TryGearStorageRedrawOnly then
                    WarbandNexus:TryGearStorageRedrawOnly()
                end
            end
            local function refreshStorageRec(equipOnly)
                st.gearStorageRecRefreshEquipOnly = equipOnly == true
                if st.gearStorageRecRefreshTimer and st.gearStorageRecRefreshTimer.Cancel then
                    st.gearStorageRecRefreshTimer:Cancel()
                end
                st.gearStorageRecRefreshTimer = nil
                local h = C_Timer.NewTimer(GEAR_STORAGE_REC_REFRESH_DEBOUNCE, runGearStorageRecRefreshNow)
                if type(h) == "table" and h.Cancel then
                    st.gearStorageRecRefreshTimer = h
                else
                    runGearStorageRecRefreshNow()
                end
            end
            local function redrawStorageRecAfterEquipChange()
                -- Unequip-to-bag / new loot: persisted itemStorage can lag; live scan needs a full Find.
                if recEnabled then
                    ScheduleGearTabInventoryNarrowRefresh()
                end
            end
            local recEnabled = WarbandNexus.IsGearStorageRecommendationsEnabled
                and WarbandNexus:IsGearStorageRecommendationsEnabled()
            local function trySlotRefresh(pl)
                if WarbandNexus.TryRefreshGearEquipSlotsOnly and WarbandNexus:TryRefreshGearEquipSlotsOnly(pl) then
                    if recEnabled then
                        redrawStorageRecAfterEquipChange()
                    end
                    return true
                end
                if f._gearDeferChainActive and WarbandNexus.TryRefreshGearEquipSlotsOnly then
                    C_Timer.After(0.15, function()
                        if HiddenOrMissing() or f.currentTab ~= "gear" then return end
                        if WarbandNexus:TryRefreshGearEquipSlotsOnly(pl) then
                            if recEnabled then
                                redrawStorageRecAfterEquipChange()
                            end
                        else
                            SchedulePopulateContent(true)
                        end
                    end)
                    return true
                end
                return false
            end
            if trySlotRefresh(payload) then
                return
            end
            if gearQuiet then
                if recEnabled then
                    redrawStorageRecAfterEquipChange()
                end
                return
            end
            SchedulePopulateContent(true)
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PVE_UPDATED, function()
        if HiddenOrMissing() then return end
        -- PvE tab + Characters tab (mythic key column reads character row; mirror updates from PvECacheService)
        if f.currentTab == "pve" then
            -- Vault data arrives asynchronously via WEEKLY_REWARDS_UPDATE.
            -- Reset cooldown so this event is never silently dropped.
            st.lastEventPopulateTime = 0
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            st.lastEventPopulateTime = 0
            SchedulePopulateContent(true)
        end
    end)
    
    -- REMOVED: WARBAND_CURRENCIES_UPDATED — no SendMessage exists for this string; dead handler.

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCY_UPDATED, function()
        if HiddenOrMissing() then return end
        if f.currentTab == "gear" then
            SchedulePopulateContent(true)
        elseif f.currentTab == "currency" then
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            -- Total Gold / WoW Token card reads token price; refresh without 800ms cooldown drop.
            SchedulePopulateContent(true)
        elseif f.currentTab == "pve" then
            -- Restored Key / crest columns: vault open grants currency before hover tooltip refresh.
            st.lastEventPopulateTime = 0
            SchedulePopulateContent(true)
        else
            WarbandNexus:UpdateTabCountBadges("currency")
        end
    end)

    -- Reputation tab content: ReputationUI.lua registers DrawReputationTab for many WN_REPUTATION_* events.
    -- Tab badge count: refresh cheaply when cache updates without full PopulateContent if user is elsewhere.
    -- ReputationUI.lua redraws the tab on these when active; only refresh the tab button badge when elsewhere.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.REPUTATION_UPDATED, function()
        if HiddenOrMissing() then return end
        if f.currentTab ~= "reputations" then
            WarbandNexus:UpdateTabCountBadges("reputations")
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.REPUTATION_CACHE_READY, function()
        if HiddenOrMissing() then return end
        if f.currentTab ~= "reputations" then
            WarbandNexus:UpdateTabCountBadges("reputations")
        end
    end)
    
    -- WN_REPUTATION_* refresh: ReputationUI.lua registers DrawReputationTab (avoid double PopulateContent here)
    
    -- Plans / To-Do: add/remove/complete need immediate redraw (skip POPULATE_COOLDOWN).
    -- try_count_set / statistic reseeds can storm during farms — coalesce via debounce + 800ms cooldown.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PLANS_UPDATED, function(_, payload)
        if not HiddenOrMissing() and f.currentTab == "plans" then
            local action = payload and payload.action
            local tryCountBurst = action == "try_count_set" or action == "statistics_reseeded"
                or action == "statistics_seeded"
            local plansCoalesce = tryCountBurst or action == "reminder_changed"
            if plansCoalesce then
                SchedulePopulateContent()
            else
                SchedulePopulateContent(true)
            end
        end
    end)
    
    -- Collection scan complete: collections needs immediate paint; plans browse coalesces (avoid redraw loop).
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.COLLECTION_SCAN_COMPLETE, function()
        if HiddenOrMissing() then return end
        local tab = f.currentTab
        if tab == "collections" then
            SchedulePopulateContent(true)
        elseif tab == "plans" then
            SchedulePopulateContent()
        end
    end)
    
    -- Profession tab: deduplicated listeners (ops-022); chars tab still updates on concentration/knowledge/equipment
    local function onProfessionsTabRefresh()
        if HiddenOrMissing() then return end
        if f.currentTab == "professions" then
            SchedulePopulateContent(true)
        end
    end
    local function onProfessionsOrCharsRefresh()
        if HiddenOrMissing() then return end
        if f.currentTab == "professions" then
            SchedulePopulateContent(true)
        elseif f.currentTab == "chars" then
            SchedulePopulateContent()
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CONCENTRATION_UPDATED, onProfessionsOrCharsRefresh)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.KNOWLEDGE_UPDATED, onProfessionsOrCharsRefresh)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PROFESSION_EQUIPMENT_UPDATED, onProfessionsOrCharsRefresh)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.RECIPE_DATA_UPDATED, onProfessionsTabRefresh)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CRAFTING_ORDERS_UPDATED, onProfessionsTabRefresh)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PROFESSION_DATA_UPDATED, onProfessionsTabRefresh)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PROFESSION_COOLDOWNS_UPDATED, onProfessionsTabRefresh)
    
    -- BAGS_UPDATED also feeds the gear-tab recommendation scan (cross-character bag items
    -- are candidates) so newly looted BoEs surface without a manual reopen.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.BAGS_UPDATED, onItemsOrBagsInventoryUpdated)

    -- Money: chars Total Gold card, gear-tab affordability (gold-only upgrades).
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.MONEY_UPDATED, function()
        if HiddenOrMissing() then return end
        if f.currentTab == "gear" then
            if WarbandNexus.TryRefreshGearUpgradeEconomy and WarbandNexus:TryRefreshGearUpgradeEconomy() then
                return
            end
            SchedulePopulateContent(true)
        elseif f.currentTab == "chars" then
            SchedulePopulateContent(true)
        end
    end)

    -- Currency variants: gear upgrade panel + currency tab depend on full currency state.
    local function refreshCurrency()
        if HiddenOrMissing() then return end
        if f.currentTab == "gear" then
            if WarbandNexus.TryRefreshGearUpgradeEconomy and WarbandNexus:TryRefreshGearUpgradeEconomy() then
                return
            end
            SchedulePopulateContent(true)
        elseif f.currentTab == "currency" then
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            -- Token card on Characters: coalesce with standard cooldown (was skipCooldown → rapid rebuilds).
            SchedulePopulateContent()
        else
            WarbandNexus:UpdateTabCountBadges("currency")
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCIES_UPDATED, refreshCurrency)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCY_GAINED, refreshCurrency)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCY_CACHE_READY, refreshCurrency)

    -- Collections: obtained/scan results + achievement tracking flips need to redraw cards.
    -- Plans tab also reads obtained state for try-counter rows; Statistics tab shows collection counts.
    local function refreshCollection()
        if HiddenOrMissing() then return end
        if f.currentTab == "collections" or f.currentTab == "plans" or f.currentTab == "stats" then
            -- Plans browse: coalesce COLLECTION_UPDATED storms during background scans (skipCooldown rebuild loop).
            if f.currentTab == "plans" then
                SchedulePopulateContent()
            else
                SchedulePopulateContent(true)
            end
        elseif f.currentTab == "chars" then
            WarbandNexus:UpdateTabCountBadges("collections")
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.COLLECTIBLE_OBTAINED, refreshCollection)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.COLLECTION_UPDATED, refreshCollection)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.ACHIEVEMENT_TRACKING_UPDATED, refreshCollection)

    -- Vault: any vault data delta (slot completion, reward available, plan completion) must
    -- propagate to PvE tab (vault card) and chars-tab vault badge.
    local function refreshVault()
        if HiddenOrMissing() then return end
        if f.currentTab == "pve" then
            st.lastEventPopulateTime = 0
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            SchedulePopulateContent(true)
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_CHECKPOINT_COMPLETED, refreshVault)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_SLOT_COMPLETED, refreshVault)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_PLAN_COMPLETED, refreshVault)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_REWARD_AVAILABLE, refreshVault)

    -- Tracking toggle changes the visible character roster on every tab that lists chars.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CHARACTER_TRACKING_CHANGED, function()
        if HiddenOrMissing() then return end
        ns._gearStorageInvGen = (ns._gearStorageInvGen or 0) + 1
        SchedulePopulateContent(true)
    end)

    -- Pure UI state (sub-tab switches, expand/collapse, column pickers, theme accent): coalesced rebuild.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, function(_, payload)
        if HiddenOrMissing() then return end
        local tab = payload and payload.tab
        if tab and f.currentTab ~= tab then return end
        local skipCooldown = true
        if payload and payload.skipCooldown == false then
            skipCooldown = false
        end
        -- Bypass POPULATE_DEBOUNCE for explicit UI gestures (e.g. Storage section expand/collapse).
        if payload and payload.instantPopulate then
            if st.pendingPopulateTimer then
                if st.pendingPopulateTimer.Cancel then
                    st.pendingPopulateTimer:Cancel()
                end
            end
            st.pendingPopulateTimer = nil
            st.populateDebounceGen = st.populateDebounceGen + 1
            st.pendingPopulateSkipCooldown = false
            if HiddenOrMissing() then return end
            st.lastEventPopulateTime = GetTime()
            local P = ns.Profiler
            local mlab = P and P.enabled and P.SliceLabel and P:SliceLabel(P.CAT.MSG, "UI_MAIN_REFRESH_instant")
            if mlab then P:Start(mlab) end
            WarbandNexus:PopulateContent()
            if mlab then P:Stop(mlab) end
            return
        end
        SchedulePopulateContent(skipCooldown)
    end)

    -- Gold management edits + bank money log: chars tab gold cards / popup.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.GOLD_MANAGEMENT_CHANGED, function()
        if not HiddenOrMissing() and f.currentTab == "chars" then
            SchedulePopulateContent(true)
        end
    end)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CHARACTER_BANK_MONEY_LOG_UPDATED, function()
        if not HiddenOrMissing() and f.currentTab == "chars" then
            SchedulePopulateContent(true)
        end
    end)

    -- Item metadata async warm-up: cross-character SV links are often cold on login.
    -- Gear tab storage recommendations rely on link-based ilvl (e.g. WuE 253 vs template 233);
    -- when the warm-up completes, re-scan so previously-skipped candidates surface.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.ITEM_METADATA_READY, function()
        if not HiddenOrMissing() and f.currentTab == "gear" then
            if WarbandNexus.TryRefreshAllGearEquipSlotIcons then
                WarbandNexus:TryRefreshAllGearEquipSlotIcons()
            end
            if WarbandNexus.IsGearStorageRecommendationsEnabled
                and WarbandNexus:IsGearStorageRecommendationsEnabled() then
                -- Do not call TryGearStorageRedrawOnly first: a strict cache hit would skip the
                -- Invalidate + narrow refresh pipeline while SV items just gained resolved ilvl data.
                -- ItemsCacheService no longer bumps `_gearStorageInvGen` per metadata batch; this path
                -- soft-invalidates stash findings and coalesces a single ScheduleResolve (debounced).
                ScheduleGearTabInventoryNarrowRefresh()
            end
        end
    end)

    -- Blizzard fires GET_ITEM_INFO_RECEIVED whenever a cold-cache hyperlink finishes
    -- async resolution. ResolveStorageItemIlvl bails out (returns 0) on cold links,
    -- so we must re-run the gear scan once the client cache warms — otherwise the
    -- recommendation list stays empty for the entire session.
    if not UIEvents._itemInfoFrame then
        -- Intentionally raw: `GET_ITEM_INFO_RECEIVED` coalesce host — no visuals (WN_FACTORY inventory).
        local infoFrame = CreateFrame("Frame")
        UIEvents._itemInfoFrame = infoFrame
        infoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        infoFrame:SetScript("OnEvent", function(_, _, itemID, success)
            if UIEvents._itemInfoHandler then
                UIEvents._itemInfoHandler(itemID, success)
            end
        end)
    end
    -- Handler is re-assigned on every registration so it closes over the current f/st;
    -- the frame and its script above are created only once.
    do
        local handler = function(itemID, success)
            if not success then return end
            if HiddenOrMissing() then return end
            if f.currentTab ~= "gear" then return end
            st.gearItemInfoCoalesceGen = st.gearItemInfoCoalesceGen + 1
            local myGen = st.gearItemInfoCoalesceGen
            if st.gearItemInfoCoalesceTimer and st.gearItemInfoCoalesceTimer.Cancel then
                st.gearItemInfoCoalesceTimer:Cancel()
                st.gearItemInfoCoalesceTimer = nil
            end
            local function runGearItemInfoBatch()
                st.gearItemInfoCoalesceTimer = nil
                if myGen ~= st.gearItemInfoCoalesceGen then return end
                if HiddenOrMissing() or f.currentTab ~= "gear" then return end
                local recOn = WarbandNexus.IsGearStorageRecommendationsEnabled
                    and WarbandNexus:IsGearStorageRecommendationsEnabled()
                local gearCanon = f._gearPopulateCanonKey
                if WarbandNexus.TryRefreshAllGearEquipSlotIcons then
                    WarbandNexus:TryRefreshAllGearEquipSlotIcons()
                end
                if not recOn or not gearCanon then return end
                -- Hyperlink warm-up storms during a yielded Find are expected; invalidating/deferring here
                -- produced scan-complete -> deferred invalidate -> immediate rescan loops ("Scanning…" flash).
                if WarbandNexus.IsGearStorageScanInFlightForCanon
                    and WarbandNexus:IsGearStorageScanInFlightForCanon(gearCanon) then
                    return
                end
                if WarbandNexus.ShouldSkipGearStorageNarrowInvalidateForRapidRescan
                    and WarbandNexus:ShouldSkipGearStorageNarrowInvalidateForRapidRescan(gearCanon) then
                    ns._gearStorageAllowEquipSigInvBypass = true
                    if WarbandNexus.RefreshGearStorageCacheEquipSigForCanon then
                        WarbandNexus:RefreshGearStorageCacheEquipSigForCanon(gearCanon)
                    end
                    if WarbandNexus.TryGearStorageRedrawOnly then
                        WarbandNexus:TryGearStorageRedrawOnly()
                    end
                    ns._gearStorageAllowEquipSigInvBypass = false
                    return
                end
                -- Prefer committed stash findings + fresh equip sig; full Invalidate only when redraw misses.
                ns._gearStorageAllowEquipSigInvBypass = true
                if WarbandNexus.RefreshGearStorageCacheEquipSigForCanon then
                    WarbandNexus:RefreshGearStorageCacheEquipSigForCanon(gearCanon)
                end
                local redrawOk = WarbandNexus.TryGearStorageRedrawOnly
                    and WarbandNexus:TryGearStorageRedrawOnly()
                ns._gearStorageAllowEquipSigInvBypass = false
                if redrawOk then return end
                ThrottledScheduleGearAsyncRepaint()
            end
            local infoDelay = IsGearTabPopulateQuiet() and 0.38 or 0.08
            if C_Timer and C_Timer.NewTimer then
                st.gearItemInfoCoalesceTimer = C_Timer.NewTimer(infoDelay, runGearItemInfoBatch)
            else
                C_Timer.After(infoDelay, runGearItemInfoBatch)
            end
        end
        UIEvents._itemInfoHandler = handler
    end

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.MODULE_TOGGLED, function(_, moduleName, enabled)
        if HiddenOrMissing() or not f.tabButtons then return end
        -- Map module name to tab key (currencies -> currency; others same)
        local tabKey = (moduleName == "currencies") and "currency" or moduleName
        UpdateTabVisibility(f)
        if f.currentTab then
            ScrollMainNavEnsureTabVisible(f, f.currentTab)
        end
        -- Only leave the tab when the module is turned off (enabling must not bounce to Characters).
        if enabled == false and f.currentTab == tabKey then
            f.currentTab = "chars"
            if WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.lastTab = "chars"
            end
            UpdateTabButtonStates(f)
            ScrollMainNavEnsureTabVisible(f, f.currentTab)
            SchedulePopulateContent()
        elseif f.currentTab == "items" and ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() == "warband"
            and (moduleName == "items" or moduleName == "storage") then
            SchedulePopulateContent(true)
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.FONT_CHANGED, function()
        if not HiddenOrMissing() then
            SchedulePopulateContent()
        end
    end)
end
