--[[ PvEUI deferred body paint (ops split) — load after PvEUI.lua + PvEUI_CharList.lua ]]
local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local SIDE_MARGIN = (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 12


--- Inner stack width after symmetric tab side insets (header/sections anchor at contentSide).
local function PvEStackBodyWidth(scrollPaintW, contentSide)
    local side = contentSide or SIDE_MARGIN
    return math.max(1, (tonumber(scrollPaintW) or 1) - 2 * side)
end

local function PvEUI_DrawPvEProgressBody(self, parent, L, opts)
    opts = opts or {}
    if not L or not L.EnsureVaultButtonColumnsForPvE or not L.EnsurePvEExtraVisibleColumns then
        return parent and (parent:GetHeight() or 1) or 0
    end
    local GetLocalizedText = L.GetLocalizedText
    local bodyOnly = opts.bodyOnly == true
    local mf = L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame
    local chrome, metrics, fixedHeader, headerParent, headerYOffset, contentSide, stackWidth, scrollTopY

    if not bodyOnly then
        ns.PvE_ClearVaultStatusScratch()
        parent._pveChunkPaintPending = nil

        chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
        metrics = (chrome and chrome.metrics) or (ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf))
        fixedHeader = mf and mf.fixedHeader
        headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
        headerYOffset = (chrome and chrome.yOffset) or 0
        contentSide = (chrome and chrome.side) or (metrics and metrics.sideMargin) or L.SIDE_MARGIN
        stackWidth = (metrics and metrics.bodyWidth and metrics.bodyWidth > 0) and metrics.bodyWidth
            or (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent))
            or math.max(200, (parent:GetWidth() or 600) - contentSide * 2)
        parent._wnPveContentSide = contentSide
        scrollTopY = (ns.UI_GetTabColumnHeaderScrollTop and ns.UI_GetTabColumnHeaderScrollTop()) or 0
    else
        contentSide = parent._wnPveContentSide or L.SIDE_MARGIN
        scrollTopY = opts.scrollTopY or ((ns.UI_GetTabColumnHeaderScrollTop and ns.UI_GetTabColumnHeaderScrollTop()) or 0)
        local mfBody = L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame
        metrics = mfBody and ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mfBody)
        stackWidth = (metrics and metrics.bodyWidth and metrics.bodyWidth > 0) and metrics.bodyWidth
            or parent._wnPveStackWidth
            or (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mfBody, parent))
            or math.max(200, (parent:GetWidth() or 600) - contentSide * 2)
    end
    
    if not bodyOnly then
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "PvECache"
        if self.db.global.pveCache and self.db.global.pveCache.version then
            local cacheVersion = self.db.global.pveCache.version or "unknown"
            dataSource = "PvECache v" .. cacheVersion
        end
        parent.dbVersionBadge = L.CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Hide empty state card (will be shown again if needed)
    L.HideEmptyStateCard(parent, "pve")
    -- Prior build used _wnPveTabContentHost; discard any orphan so scrollChild teardown stays one-level.
    local stalePveHost = parent._wnPveTabContentHost
    if stalePveHost then
        parent._wnPveTabContentHost = nil
        local rb = ns.UI_RecycleBin
        if rb and stalePveHost.SetParent then
            stalePveHost:Hide()
            stalePveHost:SetParent(rb)
        end
    end
    
    local charKey = (L.ns.UI_GetSubsidiaryCharKey and L.ns.UI_GetSubsidiaryCharKey())
        or (L.ns.CharacterService and L.ns.CharacterService.ResolveSubsidiaryCharacterKey and L.ns.CharacterService:ResolveSubsidiaryCharacterKey(L.WarbandNexus, nil))
    local pveData = self:GetPvEData(charKey)
    
    -- Check multiple data completeness signals, not just keystone
    local needsRefresh = false
    if not pveData or not pveData.keystone then
        needsRefresh = true
    elseif pveData.vaultActivities and not pveData.vaultActivities.isPostReset then
        -- Check if any unlocked vault slot is missing iLvl (server was slow)
        local vaultCategories = {"raids", "mythicPlus", "world"}
        for ci = 1, #vaultCategories do
            local cat = vaultCategories[ci]
            local activities = pveData.vaultActivities[cat]
            if activities then
                for ai = 1, #activities do
                    local a = activities[ai]
                    if a and a.progress and a.threshold and a.progress >= a.threshold then
                        if not a.rewardItemLevel or a.rewardItemLevel == 0 then
                            needsRefresh = true
                            break
                        end
                    end
                end
            end
            if needsRefresh then break end
        end
    end
    
    -- Trigger refresh if needed (rate-limited to avoid spam)
    if needsRefresh and not L.ns.PvELoadingState.isLoading then
        local timeSinceLastAttempt = time() - (L.ns.PvELoadingState.lastAttempt or 0)
        if timeSinceLastAttempt > 10 then
            L.ns.PvELoadingState.lastAttempt = time()
            -- Never run UpdatePvEData synchronously inside PopulateContent: heavy API + DB work
            -- caused multi-second frame spikes; pool teardown on tab switch then compounded the hitch.
            local deferAddon = self
            C_Timer.After(0, function()
                if not deferAddon or not deferAddon.UpdatePvEData then return end
                local mf = L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame
                if not mf or not mf:IsShown() or mf.currentTab ~= "pve" then return end
                -- VaultScanner owns OnUIInteract at login; avoid re-poking when tab refresh runs mid-session.
                if C_WeeklyRewards and C_WeeklyRewards.OnUIInteract then
                    local scannerReady = ns.VaultScanner and ns.VaultScanner.IsInitialized and ns.VaultScanner.IsInitialized()
                    if not scannerReady then
                        C_WeeklyRewards.OnUIInteract()
                    end
                end
                deferAddon:UpdatePvEData()
            end)
            C_Timer.After(3, function()
                if not deferAddon or not deferAddon.UpdatePvEData then return end
                local mf = L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame
                if not mf or not mf:IsShown() or mf.currentTab ~= "pve" then return end
                deferAddon:UpdatePvEData()
            end)
        end
    end
    end -- not bodyOnly (badge / needsRefresh prelude)

    local profile = self.db and self.db.profile
    local sortBtn
    local titleCard

    if not bodyOnly then
    local r, g, b = L.COLORS.accent[1], L.COLORS.accent[2], L.COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleTextContent = "|cff" .. hexColor .. (GetLocalizedText("PVE_TITLE", "PvE Progress")) .. "|r"
    local subtitleTextContent = GetLocalizedText("PVE_SUBTITLE", "Great Vault, Raid Lockouts & Mythic+ across your Warband")
    local tm = L.ns.UI_GetTitleCardToolbarMetrics and L.ns.UI_GetTitleCardToolbarMetrics() or {}
    local hdrGapPve = tm.gap or (L.GetLayout().HEADER_TOOLBAR_CONTROL_GAP or 8)
    local pveToolbarReserve = (L.ns.UI_ComputeTitleToolbarReserve and L.ns.UI_ComputeTitleToolbarReserve({
        168,
        tm.filterW or 96,
        tm.columnsW or 86,
        tm.toggleW or 88,
        tm.hideW or 84,
    })) or (640 + hdrGapPve)

    local hdrCache = mf and mf._pveFixedHeaderCache
    local headerDone = false
    if hdrCache and hdrCache.titleCard then
        headerYOffset = L.RepositionPveFixedHeader(mf, hdrCache, headerParent, chrome, headerYOffset, contentSide, parent)
        if ns.UI_CommitTabFixedHeader then
            ns.UI_CommitTabFixedHeader(mf, headerYOffset)
        elseif fixedHeader then
            fixedHeader:SetHeight(headerYOffset)
        end
        titleCard = hdrCache.titleCard
        sortBtn = hdrCache.sortBtn
        if ns.PvE_RefreshCurrencyDisplayToggleChrome and WarbandNexus._wnPvECurrencyViewToggleBtn then
            ns.PvE_RefreshCurrencyDisplayToggleChrome(
                WarbandNexus._wnPvECurrencyViewToggleBtn,
                WarbandNexus._wnPvECurrencyViewToggleLbl
            )
        end
        headerDone = true
    end

    if not headerDone then
    titleCard = select(1, L.ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "pve",
        titleText = titleTextContent,
        subtitleText = subtitleTextContent,
        textRightInset = pveToolbarReserve,
    }))
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    end
    
    -- Weekly reset timer (re-anchored left of toolbar buttons after they are placed)
    local CreateResetTimer = L.ns.UI_CreateResetTimer
    local titleEdgeInset = tm.edgeInset or 0
    local hdrGap = tm.gap or 8
    local resetTimer = CreateResetTimer(
        titleCard,
        "TOPRIGHT",
        0,
        0,
        function()
            -- Use centralized GetWeeklyResetTime from PlansManager
            if L.WarbandNexus.GetWeeklyResetTime then
                local resetTimestamp = L.WarbandNexus:GetWeeklyResetTime()
                return resetTimestamp - GetServerTime()
            end
            
            -- Fallback: Use Blizzard API
            if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
                return C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
            end
            
            return 0
        end
    )
    if resetTimer and resetTimer.container then
        resetTimer.container:ClearAllPoints()
    end
    
    -- Sort + section filter: buttons right-aligned (rightmost first), reset sits left of the group
    local toolbarLeft = titleCard
    local sortOptions = (L.ns.UI_BuildCharacterSortOptions and L.ns.UI_BuildCharacterSortOptions())
        or {}
    if not self.db.profile.pveSort then self.db.profile.pveSort = {} end
    if L.ns.UI_CreateCharacterTabAdvancedFilterButton and L.ns.CharacterService and L.ns.CharacterService.EnsureCustomCharacterSectionsProfile then
        L.ns.CharacterService:EnsureCustomCharacterSectionsProfile(self.db.profile)
        if not self.db.profile.pveSectionFilter then self.db.profile.pveSectionFilter = { sectionKey = "all" } end
        sortBtn = L.ns.UI_CreateCharacterTabAdvancedFilterButton(titleCard, {
            sortOptions = sortOptions,
            dbSortTable = self.db.profile.pveSort,
            sortTabId = "pve",
            dbSectionFilter = self.db.profile.pveSectionFilter,
            getCustomSections = function()
                return self.db.profile.characterCustomGroups or {}
            end,
            onRefresh = function()
                L.WarbandNexus:SendMessage(L.E.UI_MAIN_REFRESH_REQUESTED, { tab = "pve", skipCooldown = true })
            end,
            -- PvE: section filter only â€” roster edits (delete custom header) stay on Character tab.
        })
        if sortBtn then
            if L.ns.UI_AnchorTitleCardToolbarControl then
                L.ns.UI_AnchorTitleCardToolbarControl(sortBtn, titleCard, titleCard, "RIGHT", -titleEdgeInset)
            else
                sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleEdgeInset, 0)
            end
            toolbarLeft = sortBtn
        end
    elseif L.ns.UI_CreateCharacterSortDropdown then
        sortBtn = L.ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.pveSort, function()
            L.WarbandNexus:SendMessage(L.E.UI_MAIN_REFRESH_REQUESTED, { tab = "pve", skipCooldown = true })
        end, "pve")
        if L.ns.UI_AnchorTitleCardToolbarControl then
            L.ns.UI_AnchorTitleCardToolbarControl(sortBtn, titleCard, titleCard, "RIGHT", -titleEdgeInset)
        else
            sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleEdgeInset, 0)
        end
        toolbarLeft = sortBtn
    end

    if profile then
        if not profile.ui then profile.ui = {} end
        if profile.ui.pveFavoritesExpanded == nil then
            profile.ui.pveFavoritesExpanded = true
        end
        if profile.ui.pveCharactersExpanded == nil then
            profile.ui.pveCharactersExpanded = true
        end
    end

    -- Toolbar (right to left): Filter | Columns | Current | Hide | Reset
    local attachColumnsBtn = L.PvE_AttachPvEColumnsButton or (L.ns and L.ns.PvE_AttachPvEColumnsButton)
    if attachColumnsBtn and toolbarLeft then
        toolbarLeft = attachColumnsBtn(titleCard, toolbarLeft, self) or toolbarLeft
    end
    local attachCurrencyToggle = L.PvE_AttachCurrencyDisplayToggle or (L.ns and L.ns.PvE_AttachCurrencyDisplayToggle)
    if attachCurrencyToggle and toolbarLeft then
        toolbarLeft = attachCurrencyToggle(titleCard, toolbarLeft, self) or toolbarLeft
    end
    local attachHideBtn = L.PvE_AttachHideLevelFilterButton or (L.ns and L.ns.PvE_AttachHideLevelFilterButton)
    if attachHideBtn and toolbarLeft then
        toolbarLeft = attachHideBtn(titleCard, toolbarLeft, self) or toolbarLeft
    end

    if resetTimer and resetTimer.container and toolbarLeft then
        resetTimer.container:SetPoint("RIGHT", toolbarLeft, "LEFT", -hdrGap, 0)
    end

    if L.ns.UI_HideTitleCardExpandCollapseControls then
        L.ns.UI_HideTitleCardExpandCollapseControls(parent)
    end

    titleCard:Show()
    if ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight(), 0)
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) end
    else
        headerYOffset = headerYOffset + (titleCard:GetHeight() or 64)
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    end

    if mf then
        mf._pveFixedHeaderCache = {
            titleCard = titleCard,
            sortBtn = sortBtn,
            resetTimer = resetTimer and resetTimer.container,
            columnsBtn = WarbandNexus._wnPvEColumnPickerAnchorBtn,
        }
    end
    end -- not headerDone
    end -- not bodyOnly

    if bodyOnly then
        profile = profile or (self.db and self.db.profile)
    end

    local PVE_DAWNCRESTS = L.GetPvEDawnCrestColumnDefinitions()
    local PVE_RESTORED_KEY_FALLBACK_ID = 3089
    L.ResolvePveDelveCurrencyColumns(self)
    local PVE_SHARDS_ID = L._pveDelveCurrencyCache.shardsID
    local PVE_RESTORED_KEY_ID = L._pveDelveCurrencyCache.keyID
    local PVE_SHARDS_ICON = L._pveDelveCurrencyCache.shardsIcon or "Interface\\Icons\\INV_Misc_Gem_Variety_01"
    local PVE_RESTORED_KEY_ICON = L._pveDelveCurrencyCache.keyIcon or "Interface\\Icons\\INV_Misc_Key_13"
    if not PVE_RESTORED_KEY_ID then
        PVE_RESTORED_KEY_ID = PVE_RESTORED_KEY_FALLBACK_ID
    end

    profile = profile or (self.db and self.db.profile)
    local vaultCols, pveExtraCols, vbProfile, vaultTrackColW, PVE_COLUMNS
    local skipColumnBuild = bodyOnly and opts.columnDefs ~= nil
    if skipColumnBuild then
        PVE_COLUMNS = L.PveCopyColumnDefs(opts.columnDefs)
        vaultTrackColW = L._pveDrawPool.vaultTrackColW or L.PVE_VAULT_COL_W
        vaultCols = L.EnsureVaultButtonColumnsForPvE(profile)
        pveExtraCols = L.EnsurePvEExtraVisibleColumns(profile)
        vbProfile = profile and profile.vaultButton or {}
    else
    local structureColSig = L.PveBuildStructureColSig(profile)
    local poolDefs = L._pveDrawPool
    if poolDefs.columnDefsColSig == structureColSig and poolDefs.columnDefs then
        PVE_COLUMNS = L.PveCopyColumnDefs(poolDefs.columnDefs)
        vaultTrackColW = poolDefs.vaultTrackColW or L.PVE_VAULT_COL_W
        vaultCols = L.EnsureVaultButtonColumnsForPvE(profile)
        pveExtraCols = L.EnsurePvEExtraVisibleColumns(profile)
        vbProfile = profile and profile.vaultButton or {}
    else
    vaultCols = L.EnsureVaultButtonColumnsForPvE(profile)
    pveExtraCols = L.EnsurePvEExtraVisibleColumns(profile)
    vbProfile = profile and profile.vaultButton or {}
    vaultTrackColW = (L.ns.ResolveVaultTrackerColumnWidth
        and L.ns.ResolveVaultTrackerColumnWidth(vbProfile.showRewardProgress == true, vbProfile.showRewardItemLevel == true))
        or ((vbProfile.showRewardProgress and vbProfile.showRewardItemLevel) and L.PVE_VAULT_COL_REWARD_PROGRESS_W)
        or (vbProfile.showRewardProgress and L.PVE_VAULT_COL_PROGRESS_W)
        or (vbProfile.showRewardItemLevel and L.PVE_VAULT_COL_ILVL_W)
        or L.PVE_VAULT_COL_W
    PVE_COLUMNS = {}
    for i = 1, #PVE_DAWNCRESTS do
        local crestEntry = PVE_DAWNCRESTS[i]
        local ck = "crest_" .. tostring(crestEntry.id)
        if pveExtraCols[ck] ~= false then
            local crestIcon = 134400
            local crestLabel = ""
            local disp = L.GetPvECachedCurrencyDisplay(crestEntry.id)
            if disp then
                if disp.iconFileID then
                    crestIcon = disp.iconFileID
                end
                if disp.name and disp.name ~= "" and not (L.issecretvalue and L.issecretvalue(disp.name)) then
                    crestLabel = disp.name
                end
            end
            if crestLabel == "" and crestEntry.labelKey then
                crestLabel = L.GetLocalizedText(crestEntry.labelKey, "")
            end
            PVE_COLUMNS[#PVE_COLUMNS + 1] = {
                key = ck,
                label = "",
                width = L.PVE_DAWNCREST_COL_W,
                icon = crestIcon,
                crestCurrencyId = crestEntry.id,
                headerLabel = crestLabel,
            }
        end
    end
    if pveExtraCols.coffer_shards ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "coffer_shards",
            label = "",
            width = L.PVE_COFFER_COL_W,
            icon = PVE_SHARDS_ICON,
            tooltipTitle = L.GetLocalizedText("PVE_COL_COFFER_SHARDS", "Coffer Shards"),
            headerLabel = L.GetLocalizedText("PVE_COL_COFFER_SHARDS", "Coffer Shards"),
        }
    end
    if pveExtraCols.restored_key ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "restored_key",
            label = "",
            width = L.PVE_KEY_COL_W,
            icon = PVE_RESTORED_KEY_ICON,
            tooltipTitle = L.GetLocalizedText("PVE_COL_RESTORED_KEY", "Restored Key"),
            headerLabel = L.GetLocalizedText("PVE_COL_RESTORED_KEY", "Restored Key"),
        }
    end
    if pveExtraCols.shard_of_dundun ~= false then
        local dundunIcon = "Interface\\Icons\\INV_Misc_Gem_Variety_02"
        local dundunDisp = L.GetPvECachedCurrencyDisplay(L.PVE_DUNDUN_ID)
        if dundunDisp and dundunDisp.iconFileID then
            dundunIcon = dundunDisp.iconFileID
        end
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "shard_of_dundun",
            label = "",
            width = L.PVE_DUNDUN_COL_W,
            icon = dundunIcon,
            tooltipTitle = L.GetLocalizedText("PVE_COL_SHARD_OF_DUNDUN", "Shard of Dundun"),
            headerLabel = L.GetLocalizedText("PVE_COL_SHARD_OF_DUNDUN", "Shard of Dundun"),
        }
    end
    if vaultCols.voidcore ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "voidcore",
            label = "",
            width = L.PVE_VOIDCORE_COL_W,
            icon = 7658128,
            tooltipTitle = L.GetLocalizedText("PVE_COL_NEBULOUS_VOIDCORE", "Nebulous Voidcore"),
            headerLabel = L.GetLocalizedText("PVE_COL_NEBULOUS_VOIDCORE", "Nebulous Voidcore"),
        }
    end
    if vaultCols.manaflux == true then
        local manafluxIcon = "Interface\\Icons\\INV_Enchant_DustArcane"
        local mfDisp = L.GetPvECachedCurrencyDisplay(L.PVE_MANAFLUX_ID)
        if mfDisp and mfDisp.iconFileID then
            manafluxIcon = mfDisp.iconFileID
        end
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "manaflux",
            label = "",
            width = L.PVE_MANAFLUX_COL_W,
            icon = manafluxIcon,
            tooltipTitle = L.GetLocalizedText("PVE_COL_DAWNLIGHT_MANAFLUX", "Dawnlight Manaflux"),
            headerLabel = L.GetLocalizedText("PVE_COL_DAWNLIGHT_MANAFLUX", "Dawnlight Manaflux"),
        }
    end
    if vaultCols.raids ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "slot1",
            label = "",
            width = vaultTrackColW,
            icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
            tooltipTitle = GetLocalizedText("PVE_HEADER_RAIDS", "Raids"),
            headerLabel = L.GetLocalizedText("PVE_HEADER_RAID_SHORT", "Raid"),
        }
    end
    if vaultCols.mythicPlus ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "slot2",
            label = "",
            width = vaultTrackColW,
            icon = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
            tooltipTitle = GetLocalizedText("PVE_HEADER_DUNGEONS", "Dungeons"),
            headerLabel = L.GetLocalizedText("VAULT_DUNGEON", "Dungeon"),
        }
    end
    if vaultCols.world ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "slot3",
            label = "",
            width = vaultTrackColW,
            icon = "Interface\\Icons\\INV_Misc_Map_01",
            tooltipTitle = GetLocalizedText("VAULT_WORLD", "World"),
            headerLabel = L.GetLocalizedText("VAULT_SLOT_WORLD", "World"),
        }
    end
    -- Bountiful weekly â€” Trovehunter's Bounty item icon (live fileID when API returns it)
    if vaultCols.bounty ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "bountiful",
            label = "",
            width = L.PVE_BOUNTIFUL_COL_W,
            icon = L.GetTrovehunterBountyColumnIcon(),
            tooltipTitle = GetLocalizedText("BOUNTIFUL_DELVE", "Trovehunter's Bounty"),
            headerLabel = L.GetLocalizedText("PVE_HEADER_MAP_SHORT", "Bounty"),
        }
    end
    -- Vault Status â€” same Ready/Slots Earned/Pending readout as the Vault Tracker quick window.
    if vaultCols.status ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "vault_status",
            label = "",
            width = L.PVE_STATUS_COL_W,
            icon = "Interface\\RaidFrame\\ReadyCheck-Ready",
            tooltipTitle = GetLocalizedText("PVE_COL_VAULT_STATUS", "Vault Status"),
            headerLabel = L.GetLocalizedText("PVE_HEADER_STATUS_SHORT", "Status"),
            headerIconIsAtlas = false,
        }
    end

    local pveColumnSeq = L.BuildPvEColumnKeySequence(profile)
    local colOrderApi = L.ColumnOrder
    if colOrderApi and colOrderApi.SortColumnsByKeySequence then
        colOrderApi.SortColumnsByKeySequence(PVE_COLUMNS, pveColumnSeq)
    end
        poolDefs.columnDefsColSig = structureColSig
        poolDefs.columnDefs = L.PveCopyColumnDefs(PVE_COLUMNS)
        poolDefs.vaultTrackColW = vaultTrackColW
    end
    end

    local COL_SPACING = L.PVE_COL_SPACING
    local COL_RIGHT_MARGIN = L.PVE_COL_RIGHT_MARGIN
    local COL_ICON_SIZE = 24
    local COL_HEADER_HEIGHT = 48
    local visiblePveColumnKeys = {}
    local colSigParts = {}
    for i = 1, #PVE_COLUMNS do
        local ck = PVE_COLUMNS[i].key
        visiblePveColumnKeys[ck] = true
        colSigParts[i] = ck
    end
    local colSig = table.concat(colSigParts, "\1")
    local function GapBetweenColumns(leftIdx)
        local leftCol = PVE_COLUMNS[leftIdx]
        if not leftCol then return L.PVE_COL_SPACING end
        local key = leftCol.key
        if key == "manaflux" then return L.PVE_KEY_TO_VAULT_GAP end
        if key == "voidcore" and (not visiblePveColumnKeys.manaflux) then return L.PVE_KEY_TO_VAULT_GAP end
        if key == "shard_of_dundun" and (not visiblePveColumnKeys.voidcore) and (not visiblePveColumnKeys.manaflux) then
            return L.PVE_KEY_TO_VAULT_GAP
        end
        if key == "restored_key" and (not visiblePveColumnKeys.shard_of_dundun) and (not visiblePveColumnKeys.voidcore) and (not visiblePveColumnKeys.manaflux) then
            return L.PVE_KEY_TO_VAULT_GAP
        end
        if key == "slot1" or key == "slot2" then return L.PVE_VAULT_CLUSTER_GAP end
        if key == "slot3" then return L.PVE_KEY_TO_VAULT_GAP end
        return L.PVE_COL_SPACING
    end

    local rosterSigFast = L.PveBuildFastRosterSig(self, profile)
    local drawSig = opts.drawSig or L.PveBuildFullDrawSig(self, profile, rosterSigFast, colSig)
    local rosterCount = tonumber(rosterSigFast:match("^(%d+)")) or 0

    if not bodyOnly then
        if not L.ns.Utilities:IsModuleEnabled("pve") then
            L.WarbandNexus._pveVaultTooltipCharsSnapshot = {}
            local CreateDisabledCard = L.ns.UI_CreateDisabledModuleCard
            local cardHeight = CreateDisabledCard(parent, scrollTopY, GetLocalizedText("PVE_TITLE", "PvE Progress"))
            return scrollTopY + cardHeight
        end

        local chr = L._pveDrawPool.colHeaderRow
        if parent._pveBodyReady and parent._pveDrawSig == drawSig and chr and chr:GetParent() == parent then
            local contentSideCached = parent._wnPveContentSide or L.SIDE_MARGIN
            local mfCached = mf or (L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame)
            local metricsCached = mfCached and ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mfCached)
            local bodyW = (metricsCached and metricsCached.bodyWidth and metricsCached.bodyWidth > 0) and metricsCached.bodyWidth
                or parent._wnPveStackWidth
                or math.max(200, (parent:GetWidth() or 600) - contentSideCached * 2)
            local minW = parent._pveMinScrollWidth or parent:GetWidth() or 600
            local gridW = math.max(minW, bodyW + 2 * contentSideCached)
            local stackW = math.max(PvEStackBodyWidth(gridW, contentSideCached), bodyW)
            parent:SetWidth(gridW)
            parent._wnPveStackWidth = stackW
            if mf then mf._pveMinScrollWidth = gridW end
            if chr.SetWidth then
                chr:SetWidth(math.max(1, stackW))
            end
            local shells = L._pveDrawPool.sectionShells
            if shells then
                for _, sh in pairs(shells) do
                    if sh and sh.header and sh.header.SetWidth then
                        sh.header:SetWidth(math.max(1, stackW))
                    end
                    if sh and sh.body and sh.body.SetWidth then
                        sh.body:SetWidth(math.max(1, stackW))
                    end
                end
            end
            if ns.PvEUI_ApplyLivePveSectionLayout then
                ns.PvEUI_ApplyLivePveSectionLayout(nil, parent)
            end
            local coreH = parent._pvePaintedCoreH or parent._pveLastBodyEstimate
                or L.PveEstimateScrollBodyHeight(rosterCount, 4)
            if mf and ns.UI_SyncMainTabScrollChrome then
                ns.UI_SyncMainTabScrollChrome(mf, parent, coreH)
            end
            if L.ns.PvE_ColumnPickerTryRefreshAfterDraw then
                L.ns.PvE_ColumnPickerTryRefreshAfterDraw(self)
            end
            return coreH
        end

        if parent._pveDrawSig ~= drawSig then
            if ns.PvEUI and ns.PvEUI.AbortChunkedPaint then
                ns.PvEUI.AbortChunkedPaint()
            end
            L.PveTeardownKeptBodyArtifacts(parent)
        end
        parent._pvePaintedCoreH = nil

        local estH = L.PveEstimateScrollBodyHeight(rosterCount, 4)
        parent._pveLastBodyEstimate = estH
        parent._pveDrawSig = drawSig

        local PvEUIState = ns.PvEUI
        PvEUIState._bodyPaintGen = (PvEUIState._bodyPaintGen or 0) + 1
        PvEUIState._bodyPaintCtx = {
            bodyOnly = true,
            drawSig = drawSig,
            scrollTopY = scrollTopY,
            columnDefs = L.PveCopyColumnDefs(PVE_COLUMNS),
            addon = self,
            parent = parent,
        }
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                ns.PvEUI.RunDeferredBodyPaint()
            end)
        else
            ns.PvEUI.RunDeferredBodyPaint()
        end
        return estH
    end

    local yOffset = scrollTopY

    -- Check if module is disabled - show beautiful disabled state card (before column strip / scroll width)
    if not L.ns.Utilities:IsModuleEnabled("pve") then
        L.WarbandNexus._pveVaultTooltipCharsSnapshot = {}
        local CreateDisabledCard = L.ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, GetLocalizedText("PVE_TITLE", "PvE Progress"))
        return yOffset + cardHeight
    end
    
    -- Get all characters (filter tracked only for PvE display).
    -- Also honor profile.hideLowLevelThreshold: 0 (off), 80, or 90.
    local allCharacters = self:GetAllCharacters()
    local characters = {}
    local minLevel = L.GetLowLevelHideThreshold(profile)
    for i = 1, #allCharacters do
        local char = allCharacters[i]
        local lvl = tonumber(char.level) or 0
        if char.isTracked ~= false and (minLevel == 0 or lvl >= minLevel) then
            table.insert(characters, char)
        end
    end

    local function GetRowCanonicalPvEKey(char)
        return L.PvE_GetCanonicalKeyForChar(char)
    end
    
    -- Canonical key must match PvECacheService writes and GetPvEData(charKey) lookups
    local currentPlayerKey = (L.ns.UI_GetSubsidiaryCharKey and L.ns.UI_GetSubsidiaryCharKey())
        or (L.ns.CharacterService and L.ns.CharacterService.ResolveSubsidiaryCharacterKey and L.ns.CharacterService:ResolveSubsidiaryCharacterKey(L.WarbandNexus, nil))
    
    -- Load sorting preferences from profile (persistent across sessions)
    if not parent.sortPrefsLoaded then
        parent.sortKey = (L.ns.CharacterService and L.ns.CharacterService.GetTabSortKey)
            and L.ns.CharacterService:GetTabSortKey(self.db.profile, "pve") or "default"
        parent.sortAscending = self.db.profile.pveSort and self.db.profile.pveSort.ascending
        parent.sortPrefsLoaded = true
    end
    
    if not self.db.profile.pveSort then self.db.profile.pveSort = {} end
    if profile then
        if not profile.pveSectionFilter then profile.pveSectionFilter = { sectionKey = "all" } end
        if L.ns.CharacterService and L.ns.CharacterService.EnsureCustomCharacterSectionsProfile then
            L.ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
        end
    end

    local rosterSortKey = (L.ns.CharacterService and L.ns.CharacterService.GetTabSortKey)
        and L.ns.CharacterService:GetTabSortKey(profile, "pve") or "default"
    local peelCurrentChar = (rosterSortKey == "default")

    -- Use the same sorting logic as Characters tab
    local currentChar = nil
    local favorites = {}
    local regular = {}
    
    for i = 1, #characters do
        local char = characters[i]
        -- Same canonical key as PvECacheService + row loop below (vault/M+ are per-key in pveCache)
        local charKey = GetRowCanonicalPvEKey(char)
        
        if peelCurrentChar and (charKey == currentPlayerKey
            or (L.ns.VaultCharKeysMatch and L.ns.VaultCharKeysMatch(charKey, currentPlayerKey))) then
            currentChar = char
        elseif L.ns.CharacterService and L.ns.CharacterService:IsFavoriteCharacter(self, charKey) then
            table.insert(favorites, char)
        else
            table.insert(regular, char)
        end
    end
    
    -- Sort function (with custom order support, same as Characters tab)
    local function sortCharacters(list, orderKey)
        local CS = L.ns.CharacterService
        if CS and CS.SortCharacterRosterList then
            return CS:SortCharacterRosterList(list, self.db.profile, orderKey, {
                tabId = "pve",
                compareNameFn = L.CompareCharNameLower,
                isLoggedInFn = function(char)
                    return CS:IsLoggedInCharacterRow(L.WarbandNexus, GetRowCanonicalPvEKey(char))
                end,
                getCharKeyFn = GetRowCanonicalPvEKey,
            })
        end
        table.sort(list, function(a, b)
            return L.CompareCharNameLower(a, b)
        end)
        return list
    end
    
    -- Sort favorites; split non-favorites into custom sections + main list (Characters tab parity)
    favorites = sortCharacters(favorites, "favorites")
    local groupedById = {}
    local regularUngrouped = {}
    for rxi = 1, #regular do
        local rchar = regular[rxi]
        local rKey = GetRowCanonicalPvEKey(rchar)
        local gsec = L.ns.CharacterService and L.ns.CharacterService.GetCharacterCustomSectionId
            and L.ns.CharacterService:GetCharacterCustomSectionId(self, rKey) or nil
        if gsec then
            -- Keys must match gMeta.id / L.PveGroupIdFromSectionSecKey (string) â€” mixed number|string IDs broke groupedDisplay lookup.
            local gk = tostring(gsec)
            if not groupedById[gk] then groupedById[gk] = {} end
            groupedById[gk][#groupedById[gk] + 1] = rchar
        else
            regularUngrouped[#regularUngrouped + 1] = rchar
        end
    end
    local sortModeKey = rosterSortKey
    local customGroupsOrdered = {}
    if profile and L.ns.CharacterService and L.ns.CharacterService.BuildOrderedCustomCharacterGroups then
        customGroupsOrdered = L.ns.CharacterService:BuildOrderedCustomCharacterGroups(profile, sortModeKey)
    end
    for oci = 1, #customGroupsOrdered do
        local gid0 = customGroupsOrdered[oci].id
        local gk0 = tostring(gid0)
        local gL = groupedById[gk0]
        if gL and #gL > 0 then
            local lk0 = (L.ns.CharacterService and L.ns.CharacterService.GetCustomGroupListKey and L.ns.CharacterService:GetCustomGroupListKey(gid0)) or "regular"
            groupedById[gk0] = sortCharacters(gL, lk0)
        end
    end
    regularUngrouped = sortCharacters(regularUngrouped, "regular")

    -- Merge: current first (default sort only), then favorites, then each custom group, then ungrouped regular
    local sortedCharacters = {}
    if peelCurrentChar and currentChar then
        sortedCharacters[#sortedCharacters + 1] = currentChar
    end
    for fi = 1, #favorites do
        sortedCharacters[#sortedCharacters + 1] = favorites[fi]
    end
    for oci = 1, #customGroupsOrdered do
        local gid1 = customGroupsOrdered[oci].id
        local gL2 = groupedById[tostring(gid1)]
        if gL2 then
            for gj = 1, #gL2 do
                sortedCharacters[#sortedCharacters + 1] = gL2[gj]
            end
        end
    end
    for ui = 1, #regularUngrouped do
        sortedCharacters[#sortedCharacters + 1] = regularUngrouped[ui]
    end
    for gidOr, listOr in pairs(groupedById) do
        local foundOr = false
        for ociOr = 1, #customGroupsOrdered do
            if tostring(customGroupsOrdered[ociOr].id) == tostring(gidOr) then
                foundOr = true
                break
            end
        end
        if not foundOr and listOr and #listOr > 0 then
            for oj = 1, #listOr do
                sortedCharacters[#sortedCharacters + 1] = listOr[oj]
            end
        end
    end
    characters = sortedCharacters
    do
        local snap = {}
        for i = 1, #characters do
            snap[i] = characters[i]
        end
        L.WarbandNexus._pveVaultTooltipCharsSnapshot = snap
    end

    local rosterSigParts = {}
    local currentKeySet = {}
    for i = 1, #characters do
        local rk = GetRowCanonicalPvEKey(characters[i])
        if rk then
            rosterSigParts[#rosterSigParts + 1] = rk
            currentKeySet[rk] = true
        end
    end
    table.sort(rosterSigParts)
    local rosterSig = tostring(#rosterSigParts) .. "\0" .. table.concat(rosterSigParts, "\1")
    local rosterChanged = (L._pveDrawPool.rosterSig ~= rosterSig)
    L.PvESyncPvEPools(rosterSig, colSig, currentKeySet, visiblePveColumnKeys)

    if L.ns.PvELoadingState and L.ns.PvELoadingState.isLoading then
        local UI_CreateLoadingStateCard = L.ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local newYOffset = UI_CreateLoadingStateCard(
                parent,
                yOffset,
                L.ns.PvELoadingState,
                GetLocalizedText("LOADING_PVE", "Loading PvE Data...")
            )
            return newYOffset + 50
        end
    end

    if L.ns.PvELoadingState and L.ns.PvELoadingState.error and not L.ns.PvELoadingState.isLoading then
        local UI_CreateErrorStateCard = L.ns.UI_CreateErrorStateCard
        if UI_CreateErrorStateCard then
            yOffset = UI_CreateErrorStateCard(parent, yOffset, L.ns.PvELoadingState.error)
        end
    end

    if #characters == 0 then
        local _, height = L.CreateEmptyStateCard(parent, "pve", yOffset)
        return yOffset + height
    end
    
    local tempMeasure = L.PvE_GetDrawPoolMeasureFS()
    tempMeasure:Hide()
    local maxNameRealmWidth = 0
    local measureNameW = ns.PvE_MeasureStackedNameColumnWidth
    if rosterChanged and measureNameW then
        for i = 1, #characters do
            local c = characters[i]
            local k = GetRowCanonicalPvEKey(c)
            if k then
                local nameStr = c.name or "Unknown"
                if L.issecretvalue and L.issecretvalue(nameStr) then
                    nameStr = "Unknown"
                end
                local realmStr = L.ns.Utilities and L.ns.Utilities:FormatRealmName(c.realm) or c.realm or ""
                if realmStr ~= "" and L.issecretvalue and L.issecretvalue(realmStr) then
                    realmStr = ""
                end
                local w = measureNameW(tempMeasure, nameStr, realmStr)
                L._pveDrawPool.nameWidths[k] = w
                if w > maxNameRealmWidth then maxNameRealmWidth = w end
            end
        end
    else
        for i = 1, #characters do
            local k = GetRowCanonicalPvEKey(characters[i])
            if k then
                local w = L._pveDrawPool.nameWidths[k]
                if w and w > maxNameRealmWidth then maxNameRealmWidth = w end
            end
        end
    end
    local nameWidth = (ns.PvE_ResolveNameColumnWidth and ns.PvE_ResolveNameColumnWidth(maxNameRealmWidth))
        or math.max(100, math.ceil(maxNameRealmWidth) + 4)

    if #characters > 0 then
        local vbProfile = profile and profile.vaultButton or {}
        local layoutSig = L.PvE_BuildColumnLayoutSig(rosterSig, colSig, nameWidth, vbProfile)
        local layoutCache = L._pveDrawPool.columnLayout
        local layoutHit = layoutCache.sig == layoutSig and L.PvE_ApplyCachedColumnWidths(PVE_COLUMNS, layoutCache)
        if not layoutHit then
            L.PvE_ApplyAdaptiveColumnWidths(PVE_COLUMNS, {
                characters = characters,
                addon = self,
                getCharKey = GetRowCanonicalPvEKey,
                crests = PVE_DAWNCRESTS,
                shardsId = PVE_SHARDS_ID,
                keyId = PVE_RESTORED_KEY_ID,
                dundunId = L.PVE_DUNDUN_ID,
                voidcoreId = L.PVE_VOIDCORE_ID,
                manafluxId = L.PVE_MANAFLUX_ID,
                formatSeasonShift = ns.UI_FormatSeasonProgressShiftAware,
                compactShift = true,
                buildCompactHeader = function(col)
                    return L.PvE_BuildCompactHeaderLabel(col)
                end,
                formatVaultTrack = L.PvE_FormatVaultTrackColumn,
                formatNumber = L.FormatNumber,
                emDash = "\226\128\148",
                colIconSize = COL_ICON_SIZE,
            })
            L.PvE_SaveColumnLayoutCache(layoutCache, layoutSig, PVE_COLUMNS)
        end
    end

    -- Wide enough for left cluster + name + level/ilvl + inline columns â†’ horizontal scrollbar when needed
    local inlineTotal = 0
    for pci = 1, #PVE_COLUMNS do
        inlineTotal = inlineTotal + PVE_COLUMNS[pci].width
    end
    for gi = 1, #PVE_COLUMNS - 1 do
        inlineTotal = inlineTotal + GapBetweenColumns(gi)
    end
    inlineTotal = inlineTotal + COL_RIGHT_MARGIN
    local gridInlineStartX = (L.PvE_ComputeInlineColumnsStartPx and L.PvE_ComputeInlineColumnsStartPx(nameWidth)) or 400
    local pveColumnDividerXs = (L.BuildPvEInlineColumnDividerXs and L.BuildPvEInlineColumnDividerXs(gridInlineStartX, PVE_COLUMNS, GapBetweenColumns)) or {}
    local minScrollW = 2 * contentSide + gridInlineStartX + inlineTotal
    local viewportPaintW = (stackWidth and stackWidth > 0) and (stackWidth + 2 * contentSide) or minScrollW
    local pveGridW = math.max(minScrollW, viewportPaintW)
    local pveStackW = math.max(PvEStackBodyWidth(pveGridW, contentSide), stackWidth or 0)
    parent:SetWidth(pveGridW)
    parent._wnPveStackWidth = pveStackW
    if mf then
        mf._pveMinScrollWidth = pveGridW
    end

    -- Crest/vault column headers live in scrollChild (scroll with the list). Not columnHeaderClip (Professions frozen strip).
    local mainFrameRef = mf or (L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame)
    local columnHeaderClip = mainFrameRef and mainFrameRef.columnHeaderClip
    if columnHeaderClip then
        columnHeaderClip:SetHeight(1)
        columnHeaderClip:Hide()
    end

    L.PvEParkAllColHeaderLabels()
    local colHeaderRow = L._pveDrawPool.colHeaderRow
    if colHeaderRow then
        colHeaderRow:SetParent(parent)
        colHeaderRow:Show()
    else
        colHeaderRow = L.ns.UI.Factory:CreateContainer(parent, pveStackW, COL_HEADER_HEIGHT)
        if not colHeaderRow then
            colHeaderRow = CreateFrame("Frame", nil, parent)
            colHeaderRow:SetSize(pveStackW, COL_HEADER_HEIGHT)
        end
        L._pveDrawPool.colHeaderRow = colHeaderRow
    end
    colHeaderRow._wnKeepOnTabSwitch = true
    colHeaderRow:SetHeight(COL_HEADER_HEIGHT)
    colHeaderRow:ClearAllPoints()
    colHeaderRow:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -yOffset)
    if colHeaderRow.SetWidth then
        colHeaderRow:SetWidth(math.max(1, pveStackW))
    end
    if colHeaderRow.bg then
        colHeaderRow.bg:Hide()
    end

    local function BuildCompactHeaderLabel(col)
        return L.PvE_BuildCompactHeaderLabel(col)
    end

    local colX = gridInlineStartX
    for hci = 1, #PVE_COLUMNS do
        local col = PVE_COLUMNS[hci]

        if col.icon or col.iconAtlas then
            local hitW, hitH = COL_ICON_SIZE + 4, COL_ICON_SIZE + 4
            local hitFrame = L._pveDrawPool.colHeaderHits[col.key]
            if hitFrame then
                hitFrame:SetParent(colHeaderRow)
                hitFrame:Show()
            else
                local PUFHdr = L.ns.UI and L.ns.UI.Factory
                hitFrame = PUFHdr and PUFHdr:CreateContainer(colHeaderRow, hitW, hitH, false)
                if not hitFrame then
                    hitFrame = CreateFrame("Frame", nil, colHeaderRow)
                    hitFrame:SetSize(hitW, hitH)
                end
                L._pveDrawPool.colHeaderHits[col.key] = hitFrame
            end
            hitFrame:SetSize(hitW, hitH)
            hitFrame:SetPoint("LEFT", colHeaderRow, "LEFT", colX + (col.width - hitW) * 0.5, 6)

            local iconTex = hitFrame._pveIconTex
            if not iconTex then
                iconTex = hitFrame:CreateTexture(nil, "ARTWORK")
                hitFrame._pveIconTex = iconTex
            end
            iconTex:SetSize(COL_ICON_SIZE, COL_ICON_SIZE)
            iconTex:SetPoint("CENTER")
            if col.iconAtlas and iconTex.SetAtlas then
                iconTex:SetTexture(nil)
                pcall(function()
                    iconTex:SetAtlas(col.iconAtlas)
                end)
                local okAtlas = iconTex.GetAtlas and iconTex:GetAtlas()
                if not okAtlas and col.icon then
                    iconTex:SetTexture(col.icon)
                    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            elseif col.icon then
                iconTex:SetTexture(col.icon)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            if ns.UI_EnsureTextureFullColor then
                ns.UI_EnsureTextureFullColor(iconTex)
            end

            local compactLabel, compactHex = BuildCompactHeaderLabel(col)
            if compactLabel ~= "" then
                L.PvEAcquireColHeaderLabel(colHeaderRow, col.key, hitFrame, compactLabel, compactHex, col.width)
            end

            if L.ShowTooltip then
                hitFrame:EnableMouse(true)
                local tooltipTitle = col.tooltipTitle
                if not tooltipTitle then
                    if col.crestCurrencyId then
                        local meta = L.GetPvECachedCurrencyDisplay(col.crestCurrencyId)
                        tooltipTitle = meta and meta.name
                    end
                    tooltipTitle = tooltipTitle or col.key or ""
                end
                hitFrame:SetScript("OnEnter", function(self)
                    L.ShowTooltip(self, {
                        type = "custom",
                        icon = col.iconAtlas or col.icon,
                        iconIsAtlas = col.iconAtlas ~= nil,
                        title = tooltipTitle,
                        lines = {},
                    })
                end)
                hitFrame:SetScript("OnLeave", function()
                    if L.HideTooltip then L.HideTooltip() end
                end)
                L.BindForwardScrollWheel(hitFrame)
            end
        end

        colX = colX + col.width
        if hci < #PVE_COLUMNS then
            colX = colX + GapBetweenColumns(hci)
        end
    end

    if L.UI_SyncGridColumnDividers and #pveColumnDividerXs > 0 then
        L.UI_SyncGridColumnDividers(colHeaderRow, pveColumnDividerXs, COL_HEADER_HEIGHT)
    end

    colHeaderRow:Show()
    yOffset = yOffset + COL_HEADER_HEIGHT + L.PVE_COLUMN_HEADER_PAD

    parent._pveSectionShellOrder = {}
    parent._pveColHeaderBottomY = yOffset
    parent._pveShellSectionGap = 4

    local totalLHBox = { v = yOffset }
    -- Same vertical rhythm as Characters virtual rows: `betweenRows` (often 0) after each 46px row.
    local PVE_CHAR_ROW_GAP = L.GetLayout().betweenRows or 0
    local scrollFrameRef = parent:GetParent()

    local function applyPveSectionReflow(rowHost, gap)
        ns.PvEUI_ApplyLivePveSectionLayout(rowHost, parent)
    end

    local sectionFilter = "all"
    if profile and profile.pveSectionFilter and type(profile.pveSectionFilter.sectionKey) == "string" then
        sectionFilter = profile.pveSectionFilter.sectionKey
    end
    local drawFav = (sectionFilter == "all") or (sectionFilter == "favorites")
    local drawReg = (sectionFilter == "all") or (sectionFilter == "regular")

    -- Characters tab parity: the online character lives inside Favorites / a custom header / Characters,
    -- never as a separate "pinned" row (which broke layout and skipped custom-group membership).
    local favoritesDisplay = {}
    for fi = 1, #favorites do
        favoritesDisplay[fi] = favorites[fi]
    end
    local regularDisplay = {}
    for ri = 1, #regularUngrouped do
        regularDisplay[ri] = regularUngrouped[ri]
    end
    local groupedDisplay = {}
    for gid, lst in pairs(groupedById) do
        local copy = {}
        for li = 1, #lst do
            copy[li] = lst[li]
        end
        groupedDisplay[tostring(gid)] = copy
    end
    if currentChar then
        local ck0 = GetRowCanonicalPvEKey(currentChar)
        if ck0 and L.ns.CharacterService then
            local inFav = L.ns.CharacterService.IsFavoriteCharacter and L.ns.CharacterService:IsFavoriteCharacter(self, ck0)
            local curGid = (not inFav) and L.ns.CharacterService.GetCharacterCustomSectionId
                and L.ns.CharacterService:GetCharacterCustomSectionId(self, ck0) or nil
            if inFav then
                favoritesDisplay[#favoritesDisplay + 1] = currentChar
                favoritesDisplay = sortCharacters(favoritesDisplay, "favorites")
            elseif curGid then
                local gkMerge = tostring(curGid)
                local bucket = groupedDisplay[gkMerge]
                if not bucket then
                    bucket = {}
                    groupedDisplay[gkMerge] = bucket
                end
                bucket[#bucket + 1] = currentChar
                local lk0 = (L.ns.CharacterService.GetCustomGroupListKey and L.ns.CharacterService:GetCustomGroupListKey(curGid))
                    or ("group_" .. gkMerge)
                groupedDisplay[gkMerge] = sortCharacters(bucket, lk0)
            else
                regularDisplay[#regularDisplay + 1] = currentChar
                regularDisplay = sortCharacters(regularDisplay, "regular")
            end
        end
    end

    local paintOrder = {}
    if drawFav and #favoritesDisplay > 0 then
        for fi2 = 1, #favoritesDisplay do
            paintOrder[#paintOrder + 1] = { char = favoritesDisplay[fi2], secKey = "pve_fav" }
        end
    end
    for oci2 = 1, #customGroupsOrdered do
        local gMeta = customGroupsOrdered[oci2]
        local gid2 = gMeta.id
        local gList2 = groupedDisplay[tostring(gid2)] or {}
        local gListKey = (L.ns.CharacterService and L.ns.CharacterService.GetCustomGroupListKey and L.ns.CharacterService:GetCustomGroupListKey(gid2)) or ("group_" .. tostring(gid2))
        local showGrp = (sectionFilter == "all") or (sectionFilter == gListKey)
        if showGrp and #gList2 > 0 then
            local sk = "pve_grp:" .. tostring(gid2)
            for gj2 = 1, #gList2 do
                paintOrder[#paintOrder + 1] = { char = gList2[gj2], secKey = sk }
            end
        end
    end
    for gidOr2, listOr2 in pairs(groupedDisplay) do
        local foundOr2 = false
        for ociOr2 = 1, #customGroupsOrdered do
            if tostring(customGroupsOrdered[ociOr2].id) == tostring(gidOr2) then
                foundOr2 = true
                break
            end
        end
        if not foundOr2 and listOr2 and #listOr2 > 0 then
            local gListKey2 = (L.ns.CharacterService and L.ns.CharacterService.GetCustomGroupListKey and L.ns.CharacterService:GetCustomGroupListKey(gidOr2)) or ("group_" .. tostring(gidOr2))
            local showOr2 = (sectionFilter == "all") or (sectionFilter == gListKey2)
            if showOr2 then
                local sko = "pve_grp:" .. tostring(gidOr2)
                for oj2 = 1, #listOr2 do
                    paintOrder[#paintOrder + 1] = { char = listOr2[oj2], secKey = sko }
                end
            end
        end
    end
    if drawReg and #regularDisplay > 0 then
        for ri2 = 1, #regularDisplay do
            paintOrder[#paintOrder + 1] = { char = regularDisplay[ri2], secKey = "pve_reg" }
        end
    end

    do
        local seenKeys = {}
        local deduped = {}
        for poi = 1, #paintOrder do
            local ent = paintOrder[poi]
            local ck = ent.char and GetRowCanonicalPvEKey(ent.char) or nil
            local dedupeKey = (ck or ("?" .. poi)) .. "\0" .. tostring(ent.secKey or "")
            if not seenKeys[dedupeKey] then
                seenKeys[dedupeKey] = true
                deduped[#deduped + 1] = ent
            end
        end
        paintOrder = deduped
    end

    local secBodies = {}
    local layoutTailForShell = nil

    local function finalizePveSectionContent(secKey)
        if not secKey or not profile then return end
        local body = secBodies[secKey]
        if not body then return end
        local h = body._pveRunningH or 0.1
        body._wnSectionFullH = h
        if not profile.ui then profile.ui = {} end
        local expanded = false
        if secKey == "pve_fav" then
            expanded = profile.ui.pveFavoritesExpanded == true
        elseif secKey == "pve_reg" then
            expanded = profile.ui.pveCharactersExpanded == true
        elseif L.PveGroupIdFromSectionSecKey(secKey) then
            local gidStr = tostring(L.PveGroupIdFromSectionSecKey(secKey))
            if not profile.characterGroupExpanded then profile.characterGroupExpanded = {} end
            local cg = profile.characterGroupExpanded
            local ev = cg[gidStr]
            if ev == nil then
                local asNum = tonumber(gidStr)
                if asNum then
                    ev = cg[asNum]
                end
            end
            expanded = ev == true
        end
        if expanded then
            body:Show()
            ns.PvEUI_ReflowSectionCharRows(body, PVE_CHAR_ROW_GAP)
            ns.PvEUI_ReflowPveSectionShellChain(parent)
        else
            body:Hide()
            body:SetHeight(0.1)
        end
        body._pvePaintedSectionH = math.max(0.1, body._pveRunningH or body:GetHeight() or 0.1)
        layoutTailForShell = body
    end

    local prevDet = nil

    local PvEUIState = ns.PvEUI
    local function finalizePveCharPaint()
        if #paintOrder > 0 then
            finalizePveSectionContent(paintOrder[#paintOrder].secKey)
        end
    end

    local function paintPvERows(fromI, toI)
    for i = fromI, toI do
        local ent = paintOrder[i]
        local sk = ent.secKey
        local nextEnt = paintOrder[i + 1]
        local interRowGap = (nextEnt and nextEnt.secKey == sk) and PVE_CHAR_ROW_GAP or 0
        if i > 1 then
            local prevEnt = paintOrder[i - 1]
            if (sk or "") ~= (prevEnt.secKey or "") then
                finalizePveSectionContent(prevEnt.secKey)
                prevDet = nil
            end
        end

        -- All PvE character rows live under the collapsible section body (never directly under scrollChild).
        local rowHost
        if sk == "pve_fav" then
            if not secBodies[sk] then
                secBodies[sk] = L.PvEUI_CreatePvETabSectionShell(self, parent, profile, {
                    chars = favoritesDisplay,
                    headerLabel = GetLocalizedText("HEADER_FAVORITES", "Favorites"),
                    sectionUiKey = "pveFavoritesExpanded",
                    defaultExpanded = false,
                    headerAtlas = "GM-icon-assistActive-hover",
                    visualOpts = { sectionPreset = "gold" },
                    layoutTailFrame = layoutTailForShell,
                    totalLH = totalLHBox,
                    scrollFrameRef = scrollFrameRef,
                    yTop = totalLHBox.v,
                    sideMargin = contentSide,
                    stackWidth = pveStackW,
                })
            end
            rowHost = secBodies[sk]
        elseif sk == "pve_reg" then
            if not secBodies[sk] then
                secBodies[sk] = L.PvEUI_CreatePvETabSectionShell(self, parent, profile, {
                    chars = regularDisplay,
                    headerLabel = GetLocalizedText("HEADER_CHARACTERS", "Characters"),
                    sectionUiKey = "pveCharactersExpanded",
                    defaultExpanded = false,
                    headerAtlas = "GM-icon-headCount",
                    visualOpts = nil,
                    layoutTailFrame = layoutTailForShell,
                    totalLH = totalLHBox,
                    scrollFrameRef = scrollFrameRef,
                    yTop = totalLHBox.v,
                    sideMargin = contentSide,
                    stackWidth = pveStackW,
                })
            end
            rowHost = secBodies[sk]
        elseif sk and L.PveGroupIdFromSectionSecKey(sk) then
            if not secBodies[sk] then
                local gid4 = tostring(L.PveGroupIdFromSectionSecKey(sk))
                local gName = gid4
                for gi3 = 1, #customGroupsOrdered do
                    if tostring(customGroupsOrdered[gi3].id) == gid4 then
                        gName = customGroupsOrdered[gi3].name or gid4
                        break
                    end
                end
                local goldStyle = L.ns.CharacterService and L.ns.CharacterService.IsProfileCustomSectionHighlighted
                    and L.ns.CharacterService:IsProfileCustomSectionHighlighted(profile, gid4)
                secBodies[sk] = L.PvEUI_CreatePvETabSectionShell(self, parent, profile, {
                    chars = groupedDisplay[tostring(gid4)] or {},
                    headerLabel = gName,
                    sectionUiKey = nil,
                    defaultExpanded = false,
                    headerAtlas = goldStyle and "GM-icon-assistActive-hover" or "GM-icon-headCount",
                    visualOpts = {
                        sectionPreset = goldStyle and "gold" or "accent",
                        useCharacterGroupExpand = true,
                        groupId = gid4,
                    },
                    layoutTailFrame = layoutTailForShell,
                    totalLH = totalLHBox,
                    scrollFrameRef = scrollFrameRef,
                    yTop = totalLHBox.v,
                    sideMargin = contentSide,
                    stackWidth = pveStackW,
                })
            end
            rowHost = secBodies[sk]
        end
        assert(rowHost, "PvE row missing section body (sk=" .. tostring(sk) .. ")")

        local char = ent.char
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        -- Match DB keys (currency + PvE cache) â€” prefer characters table index via _key for canonical resolution.
        local charKey = GetRowCanonicalPvEKey(char)
        local isFavorite = L.ns.CharacterService and L.ns.CharacterService:IsFavoriteCharacter(self, charKey)
        
        -- Get PvE data from PvECacheService
        local pveData = self:GetPvEData(charKey) or {}
        
        -- Build legacy-compatible structure for rendering (backward compatibility)
        local pve = {
            keystone = pveData.keystone,
            vaultActivities = pveData.vaultActivities,
            hasUnclaimedRewards = pveData.vaultRewards and pveData.vaultRewards.hasAvailableRewards,
            raidLockouts = pveData.raidLockouts,
            worldBosses = pveData.worldBosses,
            mythicPlus = pveData.mythicPlus,
            delves = pveData.delves,
        }
        
        -- Only the current (online) character starts expanded; all others collapsed.
        local charExpandKey = "pve-char-" .. charKey
        local isCurrentChar = (charKey == currentPlayerKey)
            or (L.ns.VaultCharKeysMatch and L.ns.VaultCharKeysMatch(charKey, currentPlayerKey))
        local hasVaultReward = pve.hasUnclaimedRewards or false
        
        local charExpanded = L.IsExpanded(charExpandKey, false)

        local charDetailContent
        local buildPvEDetailIfNeeded

        local accVisual = L.BuildCollapsibleSectionOpts({
                bodyGetter = function() return charDetailContent end,
                -- Runs before SharedWidgets reads _wnSectionFullH for expand target height.
                persistFn = function(exp)
                    L.expandedStates[charExpandKey] = exp
                    if exp then
                        local detail = charDetailContent
                        local buildFn = detail and detail._pveBuildDetailFn
                        if buildFn then
                            buildFn()
                        elseif buildPvEDetailIfNeeded then
                            buildPvEDetailIfNeeded()
                        end
                    elseif charDetailContent then
                        charDetailContent:Hide()
                        charDetailContent:SetHeight(0.1)
                        charDetailContent._pvePaintedDetailH = 0.1
                    end
                    local host = rowHost
                    local sc = parent
                    if host and sc and C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            ns.PvEUI_ApplyLivePveSectionLayout(host, sc)
                        end)
                    elseif host and sc then
                        ns.PvEUI_ApplyLivePveSectionLayout(host, sc)
                    end
                end,
                refreshFn = function(exp)
                    if not exp then return end
                    local detail = charDetailContent
                    local buildFn = detail and detail._pveBuildDetailFn
                    if buildFn then
                        buildFn()
                    end
                    if detail and (not detail._wnSectionFullH or detail._wnSectionFullH < 2) and buildFn then
                        C_Timer.After(0, function()
                            if detail._pveBuildDetailFn then
                                detail._pveBuildDetailFn()
                            end
                            if detail._pveOnLayoutChanged and detail._wnSectionFullH then
                                local lh = math.max(0.1, detail._wnSectionFullH)
                                detail:SetHeight(lh)
                                detail:Show()
                                detail._pveOnLayoutChanged(lh)
                            end
                        end)
                    end
                end,
                -- Live expand/collapse: re-chain rows + section shells (Storage-tab pattern).
                onUpdate = function(drawH)
                    local dh = math.max(0.1, tonumber(drawH) or 0.1)
                    local collapsing = dh < 2
                    if charDetailContent then
                        charDetailContent:SetHeight(collapsing and 0.1 or dh)
                        if collapsing then
                            charDetailContent:Hide()
                            charDetailContent._pvePaintedDetailH = 0.1
                        else
                            charDetailContent._wnSectionFullH = dh
                            charDetailContent:Show()
                        end
                    end
                    applyPveSectionReflow(rowHost, interRowGap)
                end,
                onComplete = function(exp)
                    if charDetailContent then
                        if exp then
                            charDetailContent._pvePaintedDetailH = ns.PvEUI.ResolveCharDetailPaintHeight(charDetailContent)
                        else
                            charDetailContent:Hide()
                            charDetailContent:SetHeight(0.1)
                            charDetailContent._pvePaintedDetailH = 0.1
                        end
                    end
                    applyPveSectionReflow(rowHost, interRowGap)
                end,
            }) or {}
        accVisual.suppressSectionChrome = true
        accVisual.sectionHeaderHeight = 46
        -- Populate detail before reading _wnSectionFullH (persistFn); defer left false so onToggle re-reads height after build.
        accVisual.deferOnToggleUntilComplete = false

        local charHeader, charDetailContent, expandIconTex, rowReused = L.PvEAcquireCharRowFrames(rowHost, charKey)
        if not rowReused then
            charHeader, expandIconTex = L.CreateCollapsibleHeader(
                rowHost,
                "",
                charExpandKey,
                charExpanded,
                function(isExpanded)
                    if isExpanded then
                        if charDetailContent then
                            charDetailContent:Show()
                            charDetailContent:SetHeight(math.max(0.1, charDetailContent._wnSectionFullH or 0.1))
                        end
                    elseif charDetailContent then
                        charDetailContent:Hide()
                        charDetailContent:SetHeight(0.1)
                    end
                end,
                nil, nil, nil, true,
                accVisual
            )
            charDetailContent = L.ns.UI.Factory:CreateContainer(rowHost)
            charDetailContent:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, 0)
            charDetailContent:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)
            if charDetailContent.SetClipsChildren then
                charDetailContent:SetClipsChildren(true)
            end
            L._pveDrawPool.charRows[charKey] = {
                header = charHeader,
                detail = charDetailContent,
                expandIcon = expandIconTex,
            }
        end
        if charHeader then
            charHeader._wnCollVisualOpts = accVisual
        end
        if rowReused and charHeader and charDetailContent then
            charDetailContent:ClearAllPoints()
            charDetailContent:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, 0)
            charDetailContent:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)
            if charDetailContent.SetClipsChildren then
                charDetailContent:SetClipsChildren(true)
            end
        end
        if prevDet == nil then
            rowHost._pveCharKeysOrdered = {}
            rowHost._pveRunningH = 0
            charHeader:SetPoint("TOPLEFT", rowHost, "TOPLEFT", 0, 0)
            charHeader:SetPoint("TOPRIGHT", rowHost, "TOPRIGHT", 0, 0)
        else
            charHeader:SetPoint("TOPLEFT", prevDet, "BOTTOMLEFT", 0, -interRowGap)
            charHeader:SetPoint("TOPRIGHT", prevDet, "BOTTOMRIGHT", 0, -interRowGap)
        end
        rowHost._pveCharKeysOrdered = rowHost._pveCharKeysOrdered or {}
        rowHost._pveCharKeysOrdered[#rowHost._pveCharKeysOrdered + 1] = charKey
        rowHost._pveScrollChild = parent
        rowHost._pveScrollFrameRef = scrollFrameRef
        rowHost._pveRowGap = interRowGap
        if charHeader.SetClippingChildren then
            charHeader:SetClippingChildren(true)
        end

        if L.PvEUI_ApplyCharacterListRowChrome then
            L.PvEUI_ApplyCharacterListRowChrome(self, charHeader, char, {
                rowIndex = i,
                charKey = charKey,
                isFavorite = isFavorite,
                isCurrentChar = isCurrentChar,
                expandIconFrame = expandIconTex,
                nameWidth = nameWidth,
            })
        end

        totalLHBox.v = totalLHBox.v + PVE_CHAR_ROW_HEADER_H

        do
            local shardData = (PVE_SHARDS_ID and L.WarbandNexus:GetCurrencyData(PVE_SHARDS_ID, charKey)) or nil
            local shardQty = shardData and shardData.quantity or 0
            local shardMax = shardData and shardData.maxQuantity or 0
            local shardTE = shardData and shardData.totalEarned
            local shardSM = shardData and shardData.seasonMax

            local keyData = (PVE_RESTORED_KEY_ID and L.WarbandNexus:GetCurrencyData(PVE_RESTORED_KEY_ID, charKey)) or nil
            local keyQty = keyData and keyData.quantity or 0

            -- Vault summary from activities
            local vaultActs = pve.vaultActivities or {}

            -- Claimable loot: GetVaultStatusForChar (live API for current char; cache + reset for alts).
            local vaultLootClaimable = false
            local vsCached = L.PvE_GetVaultStatusCached and L.PvE_GetVaultStatusCached(L.WarbandNexus, charKey)
            if vsCached then
                vaultLootClaimable = vsCached.isReady == true
            else
                vaultLootClaimable = ns.CharHasClaimableVaultReward
                    and ns.CharHasClaimableVaultReward(charKey) == true
            end

            local profileVault = L.WarbandNexus and L.WarbandNexus.db and L.WarbandNexus.db.profile
            local vbCols = profileVault and profileVault.vaultButton or {}
            local function BuildVaultColumnBind(activityList, slotCount, typeName)
                if L.ns.VaultSlotsFromActivityList and L.ns.VaultFormatCategoryColumn then
                    local slots, catKey = L.ns.VaultSlotsFromActivityList(activityList, slotCount, typeName)
                    return {
                        slots = slots,
                        category = catKey,
                        showRewardProgress = vbCols.showRewardProgress == true,
                        showRewardItemLevel = vbCols.showRewardItemLevel == true,
                        vaultLootClaimable = vaultLootClaimable == true,
                        pveDisplayMode = true,
                    }
                end
                return nil
            end

            local function FormatVaultTrackSlots(activityList, slotCount, typeName)
                return L.PvE_FormatVaultTrackColumn(activityList, slotCount, typeName, vaultLootClaimable, 12)
            end

            --- Format currency for inline row: always show current quantity.
            local function FormatCurrencyStatus(qty)
                qty = qty or 0
                if qty > 0 then
                    return L.FormatNumber(qty)
                end
                return "\226\128\148"
            end

            local function BuildCurrencyTooltip(currencyID, currencyName, qty, maxQty, totalEarned, seasonMax)
                local lines = {}
                local currentLabel = GetLocalizedText("CURRENT_ENTRIES_LABEL", "Current:")
                local seasonLabel = GetLocalizedText("SEASON", "Season")
                local weeklyLabel = GetLocalizedText("CURRENCY_LABEL_WEEKLY", "Weekly")
                local remainingSuffix = GetLocalizedText("VAULT_REMAINING_SUFFIX", "remaining")
                local cappedText = CAPPED or "Capped"
                qty = qty or 0
                maxQty = maxQty or 0
                local sm = tonumber(seasonMax) or 0
                local teN = tonumber(totalEarned)

                if L.ns.Utilities and L.ns.Utilities.IsCofferKeyShardCurrency and L.ns.Utilities:IsCofferKeyShardCurrency(currencyID, currencyName) then
                    local wCap = tonumber(maxQty) or 0
                    local teForWeek = (teN ~= nil) and teN or 0
                    table.insert(lines, { text = string.format("%s %s", currentLabel, L.FormatNumber(qty)), color = {1, 1, 1} })
                    if wCap > 0 then
                        local remWeek = math.max(wCap - teForWeek, 0)
                        table.insert(lines, { text = string.format("%s: %s / %s", weeklyLabel, L.FormatNumber(teForWeek), L.FormatNumber(wCap)), color = {1, 1, 1} })
                        if remWeek > 0 then
                            table.insert(lines, { text = string.format("%s %s", L.FormatNumber(remWeek), remainingSuffix), color = {0.5, 1, 0.5} })
                        else
                            table.insert(lines, { text = cappedText, color = {1, 0.35, 0.35} })
                        end
                    end
                    return lines
                end

                if L.ns.Utilities and L.ns.Utilities.IsWeeklyCapCurrency and L.ns.Utilities:IsWeeklyCapCurrency(currencyID, currencyName) then
                    local wCap = tonumber(maxQty) or 0
                    local teForWeek = (teN ~= nil) and teN or 0
                    table.insert(lines, { text = string.format("%s %s", currentLabel, L.FormatNumber(qty)), color = {1, 1, 1} })
                    if wCap > 0 then
                        local remWeek = math.max(wCap - teForWeek, 0)
                        table.insert(lines, { text = string.format("%s: %s / %s", weeklyLabel, L.FormatNumber(teForWeek), L.FormatNumber(wCap)), color = {1, 1, 1} })
                        if remWeek > 0 then
                            table.insert(lines, { text = string.format("%s %s", L.FormatNumber(remWeek), remainingSuffix), color = {0.5, 1, 0.5} })
                        else
                            table.insert(lines, { text = cappedText, color = {1, 0.35, 0.35} })
                        end
                    end
                    return lines
                end

                local hasSeasonProgress = sm > 0
                if hasSeasonProgress then
                    local teForSeason = (teN ~= nil) and teN or 0
                    local remSeason = math.max(sm - teForSeason, 0)
                    table.insert(lines, { text = string.format("%s %s", currentLabel, L.FormatNumber(qty)), color = {1, 1, 1} })
                    table.insert(lines, { text = string.format("%s: %s / %s", seasonLabel, L.FormatNumber(teForSeason), L.FormatNumber(sm)), color = {1, 1, 1} })
                    if remSeason > 0 then
                        table.insert(lines, { text = string.format("%s %s", L.FormatNumber(remSeason), remainingSuffix), color = {0.5, 1, 0.5} })
                    else
                        table.insert(lines, { text = cappedText, color = {1, 0.35, 0.35} })
                    end
                    -- Crest sources: when the currency is a Dawncrest, append "Sources" block (Midnight S1 data).
                    local Constants = L.ns.Constants
                    local sources = Constants and Constants.DAWNCREST_UI and Constants.DAWNCREST_UI.SOURCES
                        and Constants.DAWNCREST_UI.SOURCES[currencyID] or nil
                    if sources and #sources > 0 then
                        table.insert(lines, { text = " ", color = {1, 1, 1} })
                        table.insert(lines, {
                            text = GetLocalizedText("CREST_SOURCES_HEADER", "Sources:"),
                            color = {1, 0.82, 0},
                        })
                        for si = 1, #sources do
                            table.insert(lines, { text = "\194\183 " .. sources[si], color = {0.82, 0.86, 0.95} })
                        end
                        if remSeason > 0 then
                            table.insert(lines, {
                                text = string.format("%s %s",
                                    L.FormatNumber(remSeason),
                                    GetLocalizedText("CREST_TO_CAP_SUFFIX", "to season cap")),
                                color = {0.55, 0.85, 0.55},
                            })
                        end
                    end
                    return lines
                end

                local cap = maxQty
                if cap and cap > 0 then
                    local rem = math.max(cap - qty, 0)
                    table.insert(lines, { text = string.format("%s / %s", L.FormatNumber(qty), L.FormatNumber(cap)), color = {1, 1, 1} })
                    if rem > 0 then
                        table.insert(lines, { text = string.format("%s %s", L.FormatNumber(rem), remainingSuffix), color = {0.5, 1, 0.5} })
                    else
                        table.insert(lines, { text = cappedText, color = {1, 0.35, 0.35} })
                    end
                    return lines
                end

                table.insert(lines, { text = L.FormatNumber(qty), color = {1, 1, 1} })
                return lines
            end

            -- Shared grid X: header + every row (see PvE_ComputeInlineColumnsStartPx / row chrome).
            local inlineX = gridInlineStartX
            local colValuesByKey = {}

            local mutedC = COLORS.textMuted or { 0.53, 0.53, 0.53, 1 }
            local brightC = COLORS.textBright or { 1, 1, 1, 1 }
            local dimHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cff888888"
            local DIM_COLOR = { mutedC[1], mutedC[2], mutedC[3] }
            local NORMAL_COLOR = { brightC[1], brightC[2], brightC[3] }
            local CAP_OPEN_COLOR = {0.5, 1, 0.5}
            local CAPPED_COLOR = {1, 0.35, 0.35}
            local EM_DASH = "\226\128\148"
            local EM_DASH_RICH = dimHex .. EM_DASH .. "|r"

            local function GetCapStateColor(currencyID, currencyName, qty, maxQty, totalEarned, seasonMax)
                if L.ns.Utilities and L.ns.Utilities.IsCofferKeyShardCurrency and L.ns.Utilities:IsCofferKeyShardCurrency(currencyID, currencyName) then
                    local cap = tonumber(maxQty) or 0
                    local teN = tonumber(totalEarned)
                    if cap > 0 and teN ~= nil then
                        return (teN >= cap) and CAPPED_COLOR or CAP_OPEN_COLOR
                    end
                    return NORMAL_COLOR
                end
                if L.ns.Utilities and L.ns.Utilities.IsWeeklyCapCurrency and L.ns.Utilities:IsWeeklyCapCurrency(currencyID, currencyName) then
                    local cap = tonumber(maxQty) or 0
                    local teN = tonumber(totalEarned)
                    if cap > 0 and teN ~= nil then
                        return (teN >= cap) and CAPPED_COLOR or CAP_OPEN_COLOR
                    end
                    return NORMAL_COLOR
                end
                local sm = tonumber(seasonMax) or 0
                if sm > 0 then
                    local teN = tonumber(totalEarned)
                    if teN == nil then
                        return NORMAL_COLOR
                    end
                    local rem = math.max(sm - teN, 0)
                    return (rem > 0) and CAP_OPEN_COLOR or CAPPED_COLOR
                end
                if maxQty and maxQty > 0 then
                    local rem = math.max(maxQty - (qty or 0), 0)
                    return (rem > 0) and CAP_OPEN_COLOR or CAPPED_COLOR
                end
                return NORMAL_COLOR
            end

            local FormatSeasonLine = L.ns.UI_FormatSeasonProgressCurrencyLine
            for i = 1, #PVE_DAWNCRESTS do
                local cd = L.WarbandNexus:GetCurrencyData(PVE_DAWNCRESTS[i].id, charKey)
                local q = cd and cd.quantity or 0
                local m = cd and cd.maxQuantity or 0
                local te = cd and cd.totalEarned
                local sm = cd and cd.seasonMax
                local txt = FormatSeasonLine and FormatSeasonLine(cd) or FormatCurrencyStatus(q)
                local tipTitle = PVE_DAWNCRESTS[i] and PVE_DAWNCRESTS[i].name or (GetLocalizedText("TAB_CURRENCY", "Currency"))
                colValuesByKey["crest_" .. tostring(PVE_DAWNCRESTS[i].id)] = {
                    text = txt,
                    richText = FormatSeasonLine ~= nil,
                    color = (not FormatSeasonLine) and ((txt == EM_DASH) and DIM_COLOR or GetCapStateColor(PVE_DAWNCRESTS[i].id, cd and cd.name, q, m, te, sm)) or nil,
                    tooltip = BuildCurrencyTooltip(PVE_DAWNCRESTS[i].id, cd and cd.name, q, m, te, sm),
                    tooltipTitle = tipTitle,
                    tooltipIcon = cd and cd.icon,
                    currencyID = PVE_DAWNCRESTS[i].id,
                    seasonProgressData = cd,  -- enables shift-aware live binding in render loop
                }
            end

            local shardTxt = FormatSeasonLine and FormatSeasonLine(shardData) or FormatCurrencyStatus(shardQty)
            colValuesByKey.coffer_shards = {
                text = shardTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((shardTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(PVE_SHARDS_ID, shardData and shardData.name, shardQty, shardMax, shardTE, shardSM)) or nil,
                tooltip = BuildCurrencyTooltip(PVE_SHARDS_ID, shardData and shardData.name, shardQty, shardMax, shardTE, shardSM),
                tooltipTitle = GetLocalizedText("PVE_COL_COFFER_SHARDS", "Coffer Shards"),
                tooltipIcon = shardData and shardData.icon,
                currencyID = PVE_SHARDS_ID,
                seasonProgressData = shardData,
            }
            local keyMax = keyData and keyData.maxQuantity or 0
            local keyTE = keyData and keyData.totalEarned
            local keySM = keyData and keyData.seasonMax
            local keyTxt = FormatSeasonLine and FormatSeasonLine(keyData) or FormatCurrencyStatus(keyQty)
            colValuesByKey.restored_key = {
                text = keyTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((keyTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(PVE_RESTORED_KEY_ID, keyData and keyData.name, keyQty, keyMax, keyTE, keySM)) or nil,
                tooltip = BuildCurrencyTooltip(PVE_RESTORED_KEY_ID, keyData and keyData.name, keyQty, keyMax, keyTE, keySM),
                tooltipTitle = GetLocalizedText("PVE_COL_RESTORED_KEY", "Restored Coffer Key"),
                tooltipIcon = keyData and keyData.icon,
                currencyID = PVE_RESTORED_KEY_ID,
                seasonProgressData = keyData,
            }
            local dundunData = L.WarbandNexus:GetCurrencyData(L.PVE_DUNDUN_ID, charKey)
            local dqty = (dundunData and tonumber(dundunData.quantity)) or 0
            local dmax = (dundunData and dundunData.maxQuantity) or 0
            local dte = dundunData and dundunData.totalEarned
            local dsm = dundunData and dundunData.seasonMax
            local dundunTxt = FormatSeasonLine and FormatSeasonLine(dundunData) or FormatCurrencyStatus(dqty)
            colValuesByKey.shard_of_dundun = {
                text = dundunTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((dundunTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(L.PVE_DUNDUN_ID, dundunData and dundunData.name, dqty, dmax, dte, dsm)) or nil,
                tooltip = BuildCurrencyTooltip(L.PVE_DUNDUN_ID, dundunData and dundunData.name, dqty, dmax, dte, dsm),
                tooltipTitle = L.GetLocalizedText("PVE_COL_SHARD_OF_DUNDUN", "Shard of Dundun"),
                tooltipIcon = dundunData and dundunData.icon,
                currencyID = L.PVE_DUNDUN_ID,
                seasonProgressData = dundunData,
            }
            local raidTotal = vaultActs.raids and #vaultActs.raids or 3
            local dungeonTotal = vaultActs.mythicPlus and #vaultActs.mythicPlus or 3
            local worldTotal = vaultActs.world and #vaultActs.world or 3
            -- Per-slot tooltip helper: shows achieved difficulty per slot (Heroic/Mythic raid, +N keys, Tier N world).
            -- Activity `level` field: raid = difficulty ID (use GetDifficultyInfo); M+ = key level int; World = tier int.
            local function FormatSlotDifficultyLabel(activity, category)
                if not activity then return nil end
                local lvl = tonumber(activity.level) or 0
                if lvl <= 0 then return nil end
                if category == "Raid" then
                    if GetDifficultyInfo then
                        local diffName = GetDifficultyInfo(lvl)
                        if diffName and diffName ~= "" then return diffName end
                    end
                    return "Difficulty " .. lvl
                elseif category == "M+" then
                    return "+" .. lvl
                else
                    return "Tier " .. lvl
                end
            end

            local function BuildVaultSlotTooltipLines(activities, category, totalSlots)
                local lines = {}
                local catTitle = (category == "Raid") and (GetLocalizedText("PVE_HEADER_RAIDS", "Raids"))
                    or (category == "M+") and (GetLocalizedText("PVE_HEADER_DUNGEONS", "Dungeons"))
                    or (GetLocalizedText("VAULT_WORLD", "World"))
                table.insert(lines, { text = catTitle, color = {1, 0.82, 0} })
                for i = 1, (totalSlots or 3) do
                    local a = activities and activities[i]
                    local prog   = a and (tonumber(a.progress) or 0) or 0
                    local thresh = a and (tonumber(a.threshold) or 0) or 0
                    local complete = thresh > 0 and prog >= thresh
                    local diffLabel = complete and FormatSlotDifficultyLabel(a, category) or nil
                    local rewardIlvl = a and (tonumber(a.rewardItemLevel) or 0) or 0
                    if complete then
                        local rhs = diffLabel or ""
                        if rewardIlvl > 0 then
                            rhs = (rhs ~= "" and (rhs .. "  ") or "")
                                .. L.GetLocalizedText("ILVL_FORMAT", "iLvl %d"):format(rewardIlvl)
                        end
                        table.insert(lines, {
                            text = L.GetLocalizedText("PVE_VAULT_SLOT_COMPLETE_FORMAT", "Slot %d: |cff80ff80\226\156\147|r %s"):format(i, rhs ~= "" and rhs or L.GetLocalizedText("PVE_VAULT_SLOT_UNLOCKED", "Unlocked")),
                            color = {0.85, 0.9, 0.95},
                        })
                    elseif thresh > 0 then
                        local shiftHeld = IsShiftKeyDown and IsShiftKeyDown()
                        local rem = thresh - prog
                        local progressLine
                        if shiftHeld and rem > 0 then
                            progressLine = L.GetLocalizedText("PVE_VAULT_SLOT_REMAINING_FORMAT", "Slot %d: |cffffcc00%d|r more"):format(i, rem)
                        else
                            progressLine = L.GetLocalizedText("PVE_VAULT_SLOT_PROGRESS_FORMAT", "Slot %d: |cffff8888%d/%d|r"):format(i, prog, thresh)
                        end
                        table.insert(lines, {
                            text = progressLine,
                            color = {0.65, 0.65, 0.65},
                        })
                    else
                        table.insert(lines, { text = L.GetLocalizedText("PVE_VAULT_SLOT_EMPTY_FORMAT", "Slot %d: \226\128\148"):format(i), color = DIM_COLOR })
                    end
                end
                return lines
            end

            colValuesByKey.slot1 = {
                text = FormatVaultTrackSlots(vaultActs.raids, raidTotal, "Raid"),
                vaultColumnData = BuildVaultColumnBind(vaultActs.raids, raidTotal, "Raid"),
                color = {1, 1, 1},
                tooltip = BuildVaultSlotTooltipLines(vaultActs.raids, "Raid", raidTotal),
                tooltipTitle = GetLocalizedText("PVE_HEADER_RAIDS", "Raids"),
            }
            colValuesByKey.slot2 = {
                text = FormatVaultTrackSlots(vaultActs.mythicPlus, dungeonTotal, "M+"),
                vaultColumnData = BuildVaultColumnBind(vaultActs.mythicPlus, dungeonTotal, "M+"),
                color = {1, 1, 1},
                tooltip = BuildVaultSlotTooltipLines(vaultActs.mythicPlus, "M+", dungeonTotal),
                tooltipTitle = GetLocalizedText("PVE_HEADER_DUNGEONS", "Dungeons"),
            }
            colValuesByKey.slot3 = {
                text = FormatVaultTrackSlots(vaultActs.world, worldTotal, "World"),
                vaultColumnData = BuildVaultColumnBind(vaultActs.world, worldTotal, "World"),
                color = {1, 1, 1},
                tooltip = BuildVaultSlotTooltipLines(vaultActs.world, "World", worldTotal),
                tooltipTitle = GetLocalizedText("VAULT_WORLD", "World"),
            }
            -- Trovehunter's Bounty / bountiful weeklies: per-character snapshot from PvE cache (not live API on every row).
            local delveChar = (pve.delves and pve.delves.character) or {}
            local bountifulDone = delveChar.bountifulComplete
            if bountifulDone == nil and isCurrentChar then
                bountifulDone = L.WarbandNexus.IsBountifulDelveWeeklyDone and L.WarbandNexus:IsBountifulDelveWeeklyDone() or false
            end
            local bountifulTitle = GetLocalizedText("BOUNTIFUL_DELVE", "Trovehunter's Bounty")
            local bountifulUnknown = (bountifulDone == nil)
            local bountifulTip = {
                {
                    text = bountifulUnknown and (GetLocalizedText("PVE_BOUNTY_NEED_LOGIN", "No saved status for this character. Log in to refresh."))
                        or (bountifulDone and (GetLocalizedText("VAULT_COMPLETED_ACTIVITIES", "Completed"))
                            or (GetLocalizedText("ACHIEVEMENT_NOT_COMPLETED", "Not Completed"))),
                    color = {1, 1, 1},
                },
            }
            colValuesByKey.bountiful = {
                text = bountifulUnknown and EM_DASH or (bountifulDone and L.VAULT_SLOT_CHECK or L.VAULT_SLOT_CROSS),
                color = bountifulUnknown and DIM_COLOR or {1, 1, 1},
                tooltip = bountifulTip,
                tooltipTitle = bountifulTitle,
                tooltipIcon = L.GetTrovehunterBountyColumnIcon(),
                pveBountyData = {
                    done = bountifulDone == true,
                    unknown = bountifulUnknown,
                },
            }
            local voidcoreData = L.WarbandNexus:GetCurrencyData(L.PVE_VOIDCORE_ID, charKey)
            local vqty = (voidcoreData and tonumber(voidcoreData.quantity)) or 0
            local vmax = (voidcoreData and voidcoreData.maxQuantity) or 0
            local vte = voidcoreData and voidcoreData.totalEarned
            local vsm = voidcoreData and voidcoreData.seasonMax
            local voidcoreTxt = FormatSeasonLine and FormatSeasonLine(voidcoreData) or FormatCurrencyStatus(vqty)
            colValuesByKey.voidcore = {
                text = voidcoreTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((voidcoreTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(L.PVE_VOIDCORE_ID, voidcoreData and voidcoreData.name, vqty, vmax, vte, vsm)) or nil,
                tooltip = BuildCurrencyTooltip(L.PVE_VOIDCORE_ID, voidcoreData and voidcoreData.name, vqty, vmax, vte, vsm),
                tooltipTitle = L.GetLocalizedText("PVE_COL_NEBULOUS_VOIDCORE", "Nebulous Voidcore"),
                tooltipIcon = voidcoreData and voidcoreData.icon,
                currencyID = L.PVE_VOIDCORE_ID,
                seasonProgressData = voidcoreData,
            }
            -- Vault Status (matches Vault Tracker quick window readout):
            --   Ready -> "Ready to Claim" (green)
            --   ReadySlots > 0 -> "<n> Slots Earned" (cyan)
            --   Pending only -> "Pending..." (gold)
            --   No progress -> em-dash dimmed
            do
                local vs = L.PvE_GetVaultStatusCached and L.PvE_GetVaultStatusCached(L.WarbandNexus, charKey)
                local statusTxt
                if not vs then
                    statusTxt = EM_DASH_RICH
                elseif vs.isReady then
                    statusTxt = "|cff44ff44" .. (GetLocalizedText("VAULT_READY_TO_CLAIM", "Ready to Claim")) .. "|r"
                elseif vs.claimedThisWeek and not vs.isReady then
                    statusTxt = "|cffffd700" .. (GetLocalizedText("VAULT_PENDING", "Pending\226\128\166")) .. "|r"
                elseif (vs.readySlots or 0) > 0 then
                    statusTxt = "|cff66ddff" .. L.GetLocalizedText("VAULT_SLOTS_SHORT_FORMAT", "%d Slots"):format(tonumber(vs.readySlots) or 0) .. "|r"
                else
                    statusTxt = "|cffffd700" .. (GetLocalizedText("VAULT_PENDING", "Pending\226\128\166")) .. "|r"
                end
                colValuesByKey.vault_status = {
                    text = statusTxt,
                    richText = true,
                }
            end

            local manafluxData = L.WarbandNexus:GetCurrencyData(L.PVE_MANAFLUX_ID, charKey)
            local manafluxQty = (manafluxData and manafluxData.quantity) or 0
            local mfMax = (manafluxData and manafluxData.maxQuantity) or 0
            local mfTe = manafluxData and manafluxData.totalEarned
            local mfSm = manafluxData and manafluxData.seasonMax
            local mfTxt = FormatSeasonLine and FormatSeasonLine(manafluxData) or FormatCurrencyStatus(manafluxQty)
            colValuesByKey.manaflux = {
                text = mfTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((mfTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(L.PVE_MANAFLUX_ID, manafluxData and manafluxData.name, manafluxQty, mfMax, mfTe, mfSm)) or nil,
                tooltip = BuildCurrencyTooltip(L.PVE_MANAFLUX_ID, manafluxData and manafluxData.name, manafluxQty, mfMax, mfTe, mfSm),
                tooltipTitle = L.GetLocalizedText("PVE_COL_DAWNLIGHT_MANAFLUX", "Dawnlight Manaflux"),
                tooltipIcon = manafluxData and manafluxData.icon,
                currencyID = L.PVE_MANAFLUX_ID,
                seasonProgressData = manafluxData,
            }

            local UnbindSeason = L.ns.UI_UnbindSeasonProgressAmount
            local UnbindVaultCol = L.ns.UI_UnbindVaultColumnDisplay
            local UnbindBounty = L.ns.UI_UnbindPvEBountyDisplay
            for ci = 1, #PVE_COLUMNS do
                local col = PVE_COLUMNS[ci]
                local val = colValuesByKey[col.key]
                if val then
                    local cw = col.width
                    local colCenterX = inlineX + cw * 0.5
                    local cell = L.PvEAcquireInlineCell(charHeader, charKey, col.key)
                    local colText = cell.fs
                    colText:SetPoint("CENTER", charHeader, "LEFT", colCenterX, 0)
                    colText:SetWidth(cw)
                    colText:SetJustifyH("CENTER")
                    if colText.SetJustifyV then colText:SetJustifyV("MIDDLE") end
                    colText:SetWordWrap(false)
                    if val.vaultColumnData and L.ns.UI_BindVaultColumnDisplay then
                        if UnbindSeason then UnbindSeason(colText) end
                        if UnbindBounty then UnbindBounty(colText) end
                        L.ns.UI_BindVaultColumnDisplay(colText, val.vaultColumnData)
                        ns.UI_SetTextColorRole(colText, "Bright")
                    elseif val.seasonProgressData and L.ns.UI_BindSeasonProgressAmount then
                        if UnbindVaultCol then UnbindVaultCol(colText) end
                        if UnbindBounty then UnbindBounty(colText) end
                        L.ns.UI_BindSeasonProgressAmount(colText, val.seasonProgressData, {
                            compactShift = true,
                            pveDisplayMode = true,
                        })
                        ns.UI_SetTextColorRole(colText, "Bright")
                    elseif val.pveBountyData and L.ns.UI_BindPvEBountyDisplay then
                        if UnbindSeason then UnbindSeason(colText) end
                        if UnbindVaultCol then UnbindVaultCol(colText) end
                        L.ns.UI_BindPvEBountyDisplay(colText, val.pveBountyData)
                        ns.UI_SetTextColorRole(colText, "Bright")
                    else
                        if UnbindSeason then UnbindSeason(colText) end
                        if UnbindVaultCol then UnbindVaultCol(colText) end
                        if UnbindBounty then UnbindBounty(colText) end
                        colText:SetText(val.text)
                        if not val.richText and val.color then
                            colText:SetTextColor(val.color[1], val.color[2], val.color[3])
                        elseif val.richText then
                            ns.UI_SetTextColorRole(colText, "Bright")
                        end
                    end
                    if val.tooltip and L.ShowTooltip then
                        local hit = cell.hit
                        if not hit then
                            local PUF = L.ns.UI and L.ns.UI.Factory
                            local cw0, ch0 = cw, math.max(L.ROW_HEIGHT or 26, charHeader:GetHeight() or 46)
                            hit = PUF and PUF:CreateContainer(charHeader, cw0, ch0, false)
                            if not hit then
                                hit = CreateFrame("Frame", nil, charHeader)
                            end
                            cell.hit = hit
                            hit:EnableMouse(true)
                            L.BindForwardScrollWheel(hit)
                        end
                        hit:SetParent(charHeader)
                        hit:SetPoint("CENTER", charHeader, "LEFT", colCenterX, 0)
                        hit:SetSize(cw, math.max(L.ROW_HEIGHT or 26, charHeader:GetHeight() or 46))
                        hit:Show()
                        hit:SetScript("OnEnter", function(self)
                            if val.currencyID then
                                L.ShowTooltip(self, {
                                    type = "currency",
                                    currencyID = val.currencyID,
                                    charKey = charKey,
                                })
                            else
                                L.ShowTooltip(self, {
                                    type = "custom",
                                    icon = val.tooltipIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                    title = val.tooltipTitle or (GetLocalizedText("TAB_CURRENCY", "Currency")),
                                    lines = val.tooltip,
                                })
                            end
                        end)
                        hit:SetScript("OnLeave", function()
                            if L.HideTooltip then L.HideTooltip() end
                        end)
                        hit:SetScript("OnMouseUp", function(_, button)
                            if button == "LeftButton" and charHeader then
                                charHeader:Click()
                            end
                        end)
                    elseif cell.hit then
                        cell.hit:Hide()
                        cell.hit:SetScript("OnEnter", nil)
                        cell.hit:SetScript("OnLeave", nil)
                        cell.hit:SetScript("OnMouseUp", nil)
                    end
                    inlineX = inlineX + cw
                    if ci < #PVE_COLUMNS then
                        inlineX = inlineX + GapBetweenColumns(ci)
                    end
                end
            end
            if L.UI_SyncGridColumnDividers and #pveColumnDividerXs > 0 then
                L.UI_SyncGridColumnDividers(charHeader, pveColumnDividerXs, charHeader:GetHeight() or PVE_CHAR_ROW_HEADER_H)
            end
        end
        
        charHeader:SetAlpha(1)

        -- BuildCollapsibleSectionOpts exposes config.onUpdate as sectionOnUpdate (not .onUpdate).
        charDetailContent._pveOnLayoutChanged = accVisual.sectionOnUpdate
        charDetailContent._pveLayoutHost = rowHost

        buildPvEDetailIfNeeded = function()
            ns.PvEUI_PopulateExpandedCharacterDetail(self, parent, charDetailContent, charExpandKey, charKey, pve, pveData, isCurrentChar)
        end
        if charDetailContent then
            charDetailContent._pveBuildDetailFn = buildPvEDetailIfNeeded
        end

        if charExpanded then
            buildPvEDetailIfNeeded()
            local dh = charDetailContent._wnSectionFullH or 200
            charDetailContent:SetHeight(dh)
            charDetailContent:Show()
            charDetailContent._pvePaintedDetailH = dh
            totalLHBox.v = totalLHBox.v + dh + interRowGap
        else
            charDetailContent:SetHeight(0.1)
            charDetailContent:Hide()
            charDetailContent._pvePaintedDetailH = 0.1
            totalLHBox.v = totalLHBox.v + 0.1 + interRowGap
        end

        local bod = secBodies[sk]
        if bod then
            local inc
            if charExpanded then
                -- interRowGap: same-section next row only (matches SetPoint gap); not afterElement (that duplicated the anchor gap).
                inc = PVE_CHAR_ROW_HEADER_H + (charDetailContent._wnSectionFullH or 200) + interRowGap
            else
                inc = PVE_CHAR_ROW_HEADER_H + 0.1 + interRowGap
            end
            bod._pveRunningH = (bod._pveRunningH or 0) + inc
            bod._pvePaintedSectionH = bod._pveRunningH
        end

        prevDet = charDetailContent

    -- Character sections flow directly one after another (like Characters tab)
    end
    end

    local chunkPaintScheduled = false
    local estimatedBodyH = totalLHBox.v + 12
    if #paintOrder > 0 then
        estimatedBodyH = estimatedBodyH + #paintOrder * (PVE_CHAR_ROW_HEADER_H + PVE_CHAR_ROW_GAP) + 80
        local pvePaintDrawGen = PvEUIState._paintDrawGen or 0
        local pveChunkSize = PvEUIState.PAINT_CHUNK_SIZE or 2
        local pvePaintCursor = 1

        if #paintOrder <= 1 then
            paintPvERows(1, #paintOrder)
            finalizePveCharPaint()
            estimatedBodyH = totalLHBox.v + 12
        else
            chunkPaintScheduled = true
            parent._pveChunkPaintPending = true
            local function pumpPvePaint()
                if PvEUIState._paintDrawGen ~= pvePaintDrawGen then
                    parent._pveChunkPaintPending = nil
                    return
                end
                if not mf or not mf:IsShown() or mf.currentTab ~= "pve" then
                    parent._pveChunkPaintPending = nil
                    return
                end
                local toI = math.min(pvePaintCursor + pveChunkSize - 1, #paintOrder)
                paintPvERows(pvePaintCursor, toI)
                pvePaintCursor = toI + 1
                if pvePaintCursor > #paintOrder then
                    finalizePveCharPaint()
                    if ns.PvEUI_ApplyLivePveSectionLayout then
                        ns.PvEUI_ApplyLivePveSectionLayout(nil, parent)
                    end
                    local coreHDone = parent._pvePaintedCoreH or (totalLHBox.v + 12)
                    parent._pvePaintedCoreH = coreHDone
                    parent._pveChunkPaintPending = nil
                    if mf and ns.UI_SyncMainTabScrollChrome then
                        ns.UI_SyncMainTabScrollChrome(mf, parent, coreHDone)
                    end
                    return
                end
                if mf and ns.UI_SyncMainTabScrollChrome then
                    ns.UI_SyncMainTabScrollChrome(mf, parent, totalLHBox.v + 12)
                end
                C_Timer.After(0, pumpPvePaint)
            end
            C_Timer.After(0, pumpPvePaint)
        end
    end

    local coreH = chunkPaintScheduled and estimatedBodyH or (totalLHBox.v + 12)
    if not chunkPaintScheduled and ns.PvEUI_ApplyLivePveSectionLayout then
        ns.PvEUI_ApplyLivePveSectionLayout(nil, parent)
        coreH = parent._pvePaintedCoreH or coreH
    end
    parent._pvePaintedCoreH = coreH
    parent._pveBodyReady = true
    parent._pveDrawSig = drawSig
    parent._pveLastBodyEstimate = coreH
    if not chunkPaintScheduled and mf and ns.UI_SyncMainTabScrollChrome then
        ns.UI_SyncMainTabScrollChrome(mf, parent, coreH)
    end
    if L.ns.PvE_ColumnPickerTryRefreshAfterDraw then
        L.ns.PvE_ColumnPickerTryRefreshAfterDraw(self)
    end
    return coreH
end

function ns.PvEUI.RunDeferredBodyPaint()
    local PvEUIState = ns.PvEUI
    local ctx = PvEUIState._bodyPaintCtx
    if not ctx then return end
    PvEUIState._bodyPaintCtx = nil
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "pve" then return end
    if InCombatLockdown and InCombatLockdown() then
        PvEUIState._bodyPaintCtx = ctx
        if C_Timer and C_Timer.After then
            C_Timer.After(0, ns.PvEUI.RunDeferredBodyPaint)
        end
        return
    end
    PvEUI_DrawPvEProgressBody(ctx.addon, ctx.parent, ns.PvEDrawLibs, ctx)
end

ns.PvEUI = ns.PvEUI or {}
ns.PvEUI.PvEUI_DrawPvEProgressBody = PvEUI_DrawPvEProgressBody
