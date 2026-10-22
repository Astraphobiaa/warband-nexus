--[[
    Warband Nexus - Settings UI shortcuts panel (minimap button, Easy Access launcher).
    Split from SettingsUI.lua (BuildSettings panel body; file size / Lua 5.1 limits).
    Loaded after Modules/UI/SettingsUI.lua: helpers come from ns.SettingsUI._H at call time.
]]

local ADDON_NAME, ns = ...
local M = ns.SettingsUI
assert(M and M._H, "SettingsUI_Access.lua loaded before SettingsUI.lua - check the TOC")

---@param ctx table `{ parent, effectiveWidth, sideInset, yOffset, skipPanelIntro, AnchorSectionTop }`
---@return number yOffset
function M.AppendAccessPanel(ctx)
    local H = M._H
    local WarbandNexus = H.WarbandNexus
    local ADDON_NAME = H.ADDON_NAME
    local LDBI = H.LDBI
    local ns = H.ns
    local SETTINGS_SECTION_GAP = H.SETTINGS_SECTION_GAP
    local GetSettingsSectionContentWidth = H.GetSettingsSectionContentWidth
    local AppendSettingsPanelIntro = H.AppendSettingsPanelIntro
    local AppendSettingsSubSectionHeader = H.AppendSettingsSubSectionHeader
    local StackSettingsSubPanel = H.StackSettingsSubPanel
    local CreateSection = H.CreateSection
    local CreateCheckboxGrid = H.CreateCheckboxGrid
    local CreateSliderWidget = H.CreateSliderWidget
    local FinalizeSettingsSectionHeight = H.FinalizeSettingsSectionHeight
    local SettingsMeasuredSectionContentHeight = H.SettingsMeasuredSectionContentHeight
    local MakeLauncherLeftClickCheckboxOption = H.MakeLauncherLeftClickCheckboxOption
    local WireLauncherLeftClickCheckbox = H.WireLauncherLeftClickCheckbox
    local SyncSettingsCheckboxChecked = H.SyncSettingsCheckboxChecked
    local sliderElements = H.sliderElements
    local parent = ctx.parent
    local effectiveWidth = ctx.effectiveWidth
    local sideInset = ctx.sideInset
    local yOffset = ctx.yOffset
    local skipPanelIntro = ctx.skipPanelIntro
    local AnchorSectionTop = ctx.AnchorSectionTop

    -- SHORTCUTS (minimap button + Easy Access floating shortcut)
    yOffset = AppendSettingsPanelIntro(parent, "access", effectiveWidth, yOffset, sideInset, skipPanelIntro)
    local vaultSection = CreateSection(parent, nil, effectiveWidth)
    AnchorSectionTop(vaultSection, yOffset)

    local function GetVaultButtonSettings()
        WarbandNexus.db.profile.vaultButton = WarbandNexus.db.profile.vaultButton or {}
        local settings = WarbandNexus.db.profile.vaultButton
        if settings.enabled == nil then settings.enabled = true end
        if settings.hideUntilMouseover == nil then settings.hideUntilMouseover = false end
        if settings.hideUntilReady == nil then settings.hideUntilReady = false end
        if settings.showRealmName == nil then settings.showRealmName = false end
        if settings.showRewardItemLevel == nil then settings.showRewardItemLevel = false end
        if settings.showRewardProgress == nil then settings.showRewardProgress = false end
        if settings.showManaflux == nil then settings.showManaflux = false end
        if settings.showSummaryOnMouseover == nil then settings.showSummaryOnMouseover = false end
        if settings.leftClickAction == nil and settings.leftClickQuickView == true then settings.leftClickAction = "vault" end
        local VB = ns.VaultButton
        if VB and VB.NormalizeLeftClickAction then
            settings.leftClickAction = VB.NormalizeLeftClickAction(settings.leftClickAction)
        end
        if settings.includeBountyOnly == nil then settings.includeBountyOnly = false end
        settings.columns = settings.columns or {}
        if settings.columns.raids == nil then settings.columns.raids = true end
        if settings.columns.mythicPlus == nil then settings.columns.mythicPlus = true end
        if settings.columns.world == nil then settings.columns.world = true end
        if settings.columns.bounty == nil then settings.columns.bounty = true end
        if settings.columns.voidcore == nil then settings.columns.voidcore = true end
        if settings.columns.manaflux == nil then settings.columns.manaflux = settings.showManaflux == true end
        if settings.columns.gildedStash == nil then settings.columns.gildedStash = false end
        settings.showManaflux = settings.columns.manaflux == true
        settings.opacity = tonumber(settings.opacity) or 1.0
        if ns.EnsureVaultButtonDisplaySettings then
            ns.EnsureVaultButtonDisplaySettings(settings)
        end
        return settings
    end

    local RefreshVaultButton

    local function VaultDisplayGet(key)
        local settings = GetVaultButtonSettings()
        return settings.display and settings.display[key] == true
    end

    local function VaultDisplaySet(key, value)
        local settings = GetVaultButtonSettings()
        settings.display[key] = value and true or false
        RefreshVaultButton()
    end

    local function VaultDisplayCheckbox(displayKey, labelKey, descKey, labelFallback, descFallback)
        return {
            key = "vaultDisplay_" .. displayKey,
            label = (ns.L and ns.L[labelKey]) or labelFallback,
            tooltip = (ns.L and ns.L[descKey]) or descFallback,
            get = function() return VaultDisplayGet(displayKey) end,
            set = function(v) VaultDisplaySet(displayKey, v) end,
        }
    end

    RefreshVaultButton = function()
        if WarbandNexus.RefreshVaultButtonSettings then
            WarbandNexus:RefreshVaultButtonSettings()
        end
    end

    local function IsLeftClickAction(action)
        return GetVaultButtonSettings().leftClickAction == action
    end

    local function SetLeftClickAction(action, value)
        local settings = GetVaultButtonSettings()
        if value then
            settings.leftClickAction = action
        elseif settings.leftClickAction == action then
            settings.leftClickAction = "pve"
        end
        RefreshVaultButton()
    end

    local vaultOptions = {
        {
            key = "vaultButtonEnabled",
            label = (ns.L and ns.L["CONFIG_VAULT_OPT_ENABLED"]) or "Enable Easy Access",
            tooltip = (ns.L and ns.L["CONFIG_VAULT_OPT_ENABLED_DESC"]) or "Show the draggable Easy Access shortcut on screen.",
            get = function() return GetVaultButtonSettings().enabled ~= false end,
            set = function(value)
                GetVaultButtonSettings().enabled = value
                RefreshVaultButton()
            end,
        },
        {
            key = "vaultButtonMouseover",
            label = (ns.L and ns.L["CONFIG_VAULT_OPT_MOUSEOVER"]) or "Hide Until Mouseover",
            tooltip = (ns.L and ns.L["CONFIG_VAULT_OPT_MOUSEOVER_DESC"]) or "Keep Easy Access invisible until the cursor is over its saved position.",
            get = function() return GetVaultButtonSettings().hideUntilMouseover == true end,
            set = function(value)
                GetVaultButtonSettings().hideUntilMouseover = value
                RefreshVaultButton()
            end,
        },
        {
            key = "vaultButtonSummaryMouseover",
            label = (ns.L and ns.L["CONFIG_VAULT_OPT_SUMMARY_MOUSEOVER"]) or "Warband Summary Mouseover",
            tooltip = (ns.L and ns.L["CONFIG_VAULT_OPT_SUMMARY_MOUSEOVER_DESC"]) or "Show the warband's vault summary on mouseover. Turning this off shows the current character's only.",
            get = function() return GetVaultButtonSettings().showSummaryOnMouseover == true end,
            set = function(value)
                GetVaultButtonSettings().showSummaryOnMouseover = value
                RefreshVaultButton()
            end,
        },
    }

    local vaultContentW = GetSettingsSectionContentWidth(effectiveWidth)
    local vaultStackY = 0
    local leftClickWidgets

    local leftClickOptions = {}
    local VB = ns.VaultButton
    local leftClickOrder = (VB and VB.LAUNCHER_LEFT_CLICK_ORDER) or { "pve", "chars", "vault", "saved", "plans" }
    local actionDefs = (VB and VB.LAUNCHER_ACTION_DEFS) or {}
    for li = 1, #leftClickOrder do
        local actionId = leftClickOrder[li]
        local def = actionDefs[actionId]
        if def and def.settingsLabelKey then
            leftClickOptions[#leftClickOptions + 1] = MakeLauncherLeftClickCheckboxOption(
                "vaultButtonLeftClick_",
                actionId,
                def,
                IsLeftClickAction,
                SetLeftClickAction
            )
        end
    end

    vaultStackY = StackSettingsSubPanel(vaultSection.content, vaultContentW, 0, function(inner, iw)
        local cy = 0

        -- === Minimap Button (moved here from General so all launcher shortcuts live together) ===
        local VBm = ns.VaultButton
        local function GetMinimapClickSettings()
            WarbandNexus.db.profile.minimap = WarbandNexus.db.profile.minimap or {}
            local settings = WarbandNexus.db.profile.minimap
            if settings.leftClickAction == nil then
                settings.leftClickAction = "toggle"
            end
            if VBm and VBm.NormalizeMinimapLeftClickAction then
                settings.leftClickAction = VBm.NormalizeMinimapLeftClickAction(settings.leftClickAction)
            elseif settings.leftClickAction ~= "toggle" then
                settings.leftClickAction = "toggle"
            end
            return settings
        end
        local function IsMinimapLeftClickAction(action)
            return GetMinimapClickSettings().leftClickAction == action
        end
        local function SetMinimapLeftClickAction(action, value)
            local settings = GetMinimapClickSettings()
            if value then
                settings.leftClickAction = action
            elseif settings.leftClickAction == action then
                settings.leftClickAction = "toggle"
            end
        end
        local minimapVisibilityOptions = {
            {
                key = "minimapVisible",
                label = (ns.L and ns.L["CONFIG_MINIMAP"]) or "Minimap Button",
                tooltip = (ns.L and ns.L["CONFIG_MINIMAP_DESC"]) or "Show a button on the minimap for quick access.",
                get = function() return not WarbandNexus.db.profile.minimap.hide end,
                set = function(value)
                    if WarbandNexus.SetMinimapButtonVisible then
                        WarbandNexus:SetMinimapButtonVisible(value)
                    else
                        WarbandNexus.db.profile.minimap.hide = not value
                    end
                end,
            },
            {
                key = "minimapLock",
                label = (ns.L and ns.L["LOCK_MINIMAP_ICON"]) or "Lock Minimap Button",
                tooltip = (ns.L and ns.L["LOCK_MINIMAP_TOOLTIP"]) or "Lock the minimap button in place so it cannot be dragged",
                get = function() return WarbandNexus.db.profile.minimap.lock end,
                set = function(value)
                    WarbandNexus.db.profile.minimap.lock = value
                    if LDBI then
                        local button = LDBI:GetMinimapButton(ADDON_NAME)
                        if button then
                            if value then
                                button:SetMovable(false)
                                button:RegisterForDrag()
                            else
                                button:SetMovable(true)
                                button:RegisterForDrag("LeftButton")
                            end
                        end
                    end
                end,
            },
        }
        local minimapLeftClickOptions = {
            {
                key = "minimapLeftClickToggle",
                label = (ns.L and ns.L["CONFIG_MINIMAP_LEFT_CLICK_TOGGLE"]) or "Left Click: Toggle Window",
                tooltip = (ns.L and ns.L["CONFIG_MINIMAP_LEFT_CLICK_TOGGLE_DESC"]) or "Left-clicking the minimap button opens or closes the main window (previous default).",
                get = function() return IsMinimapLeftClickAction("toggle") end,
                set = function(value) SetMinimapLeftClickAction("toggle", value) end,
            },
        }
        local mmLeftClickOrder = (VBm and VBm.LAUNCHER_LEFT_CLICK_ORDER) or {}
        local mmActionDefs = (VBm and VBm.LAUNCHER_ACTION_DEFS) or {}
        for li = 1, #mmLeftClickOrder do
            local actionId = mmLeftClickOrder[li]
            local def = mmActionDefs[actionId]
            if def and def.settingsLabelKey then
                minimapLeftClickOptions[#minimapLeftClickOptions + 1] = MakeLauncherLeftClickCheckboxOption(
                    "minimapLeftClick_",
                    actionId,
                    def,
                    IsMinimapLeftClickAction,
                    SetMinimapLeftClickAction
                )
            end
        end
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_MINIMAP_BUTTON"]) or "Minimap Button",
            iw, cy, { skipGapBefore = true })
        cy = CreateCheckboxGrid(inner, minimapVisibilityOptions, cy, iw)
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["CONFIG_MINIMAP_LEFT_CLICK_HEADER"]) or "Minimap Left Click",
            iw, cy, { compact = true })
        local minimapLeftClickYOffset, minimapLeftClickWidgets
        minimapLeftClickYOffset, minimapLeftClickWidgets = CreateCheckboxGrid(inner, minimapLeftClickOptions, cy, iw)
        local function SyncMinimapLeftClickWidgets()
            if not minimapLeftClickWidgets then return end
            for li = 1, #minimapLeftClickOptions do
                local opt = minimapLeftClickOptions[li]
                local widget = minimapLeftClickWidgets[opt.key]
                if widget and widget.checkbox then
                    local checked = opt.get and opt.get() or false
                    SyncSettingsCheckboxChecked(widget.checkbox, checked)
                end
            end
        end
        for li = 1, #minimapLeftClickOptions do
            local opt = minimapLeftClickOptions[li]
            local widget = minimapLeftClickWidgets and minimapLeftClickWidgets[opt.key]
            if widget and widget.checkbox then
                if opt._wnActionId then
                    WireLauncherLeftClickCheckbox(widget, opt._wnActionId, SetMinimapLeftClickAction, SyncMinimapLeftClickWidgets)
                elseif opt.set then
                    widget.checkbox:SetScript("OnClick", function(self)
                        opt.set(self:GetChecked())
                        SyncMinimapLeftClickWidgets()
                    end)
                end
            end
        end
        cy = minimapLeftClickYOffset

        -- === Easy Access floating button ===
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_VAULT_GENERAL"]) or "Shortcut behavior",
            iw, cy, {})
        cy = CreateCheckboxGrid(inner, vaultOptions, cy, iw)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["CONFIG_VAULT_LEFT_CLICK_HEADER"]) or "Left Click",
            iw, cy, {})
        local leftClickYOffset
        leftClickYOffset, leftClickWidgets = CreateCheckboxGrid(inner, leftClickOptions, cy, iw)

        local function SyncLeftClickWidgets()
            if not leftClickWidgets then return end
            for li = 1, #leftClickOptions do
                local opt = leftClickOptions[li]
                local actionId = opt._wnActionId
                local widget = leftClickWidgets[opt.key]
                if widget and widget.checkbox and actionId then
                    SyncSettingsCheckboxChecked(widget.checkbox, IsLeftClickAction(actionId))
                end
            end
        end
        for li = 1, #leftClickOptions do
            local opt = leftClickOptions[li]
            local widget = leftClickWidgets and leftClickWidgets[opt.key]
            WireLauncherLeftClickCheckbox(widget, opt._wnActionId, SetLeftClickAction, SyncLeftClickWidgets)
        end

        cy = leftClickYOffset

        local tooltipDisplayOptions = {
            VaultDisplayCheckbox("tooltipVault", "CONFIG_VAULT_DISPLAY_VAULT", "CONFIG_VAULT_DISPLAY_VAULT_DESC",
                "Great Vault progress", "Raid, dungeon, and world slots plus claim status."),
            VaultDisplayCheckbox("tooltipGold", "CONFIG_VAULT_DISPLAY_GOLD", "CONFIG_VAULT_DISPLAY_GOLD_DESC",
                "Gold", "Character gold on the hover tooltip."),
            VaultDisplayCheckbox("tooltipTodo", "CONFIG_VAULT_DISPLAY_TODO", "CONFIG_VAULT_DISPLAY_TODO_DESC",
                "Character to-do plans", "Active plan count for that character."),
            VaultDisplayCheckbox("tooltipBounty", "CONFIG_VAULT_DISPLAY_BOUNTY", "CONFIG_VAULT_DISPLAY_BOUNTY_DESC",
                "Trovehunter's Bounty", "Weekly delve bounty status."),
            VaultDisplayCheckbox("tooltipVoidcore", "CONFIG_VAULT_DISPLAY_VOIDCORE", "CONFIG_VAULT_DISPLAY_VOIDCORE_DESC",
                "Nebulous Voidcore", "Season voidcore progress."),
            VaultDisplayCheckbox("tooltipGildedStash", "CONFIG_VAULT_DISPLAY_STASH", "CONFIG_VAULT_DISPLAY_STASH_DESC",
                "Gilded Stashes", "Weekly gilded stash claims."),
            VaultDisplayCheckbox("tooltipManaflux", "CONFIG_VAULT_DISPLAY_MANAFLUX", "CONFIG_VAULT_DISPLAY_MANAFLUX_DESC",
                "Dawnlight Manaflux", "Held manaflux currency."),
            VaultDisplayCheckbox("tooltipKeystone", "CONFIG_VAULT_DISPLAY_KEYSTONE", "CONFIG_VAULT_DISPLAY_KEYSTONE_DESC",
                "Mythic+ keystone", "Owned keystone level and dungeon."),
            VaultDisplayCheckbox("tooltipMythicScore", "CONFIG_VAULT_DISPLAY_MYTHIC_SCORE", "CONFIG_VAULT_DISPLAY_MYTHIC_SCORE_DESC",
                "Mythic+ rating", "Overall Mythic+ score."),
        }
        local menuDisplayOptions = {
            VaultDisplayCheckbox("menuVault", "CONFIG_VAULT_DISPLAY_MENU_VAULT", "CONFIG_VAULT_DISPLAY_MENU_VAULT_DESC",
                "Vault summary block", "Raid, dungeon, world, and status under the menu title."),
            VaultDisplayCheckbox("menuKeystone", "CONFIG_VAULT_DISPLAY_MENU_KEYSTONE", "CONFIG_VAULT_DISPLAY_MENU_KEYSTONE_DESC",
                "Keystone line", "Current character keystone in the menu."),
            VaultDisplayCheckbox("menuMythicScore", "CONFIG_VAULT_DISPLAY_MENU_SCORE", "CONFIG_VAULT_DISPLAY_MENU_SCORE_DESC",
                "M+ rating line", "Overall Mythic+ score in the menu."),
        }

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_VAULT_DISPLAY"]) or "Tooltip & Menu",
            iw, cy, {})
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["CONFIG_VAULT_DISPLAY_TOOLTIP_HEADER"]) or "Hover tooltip",
            iw, cy, { compact = true })
        cy = CreateCheckboxGrid(inner, tooltipDisplayOptions, cy, iw)
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["CONFIG_VAULT_DISPLAY_MENU_HEADER"]) or "Right-click menu",
            iw, cy, { compact = true })
        cy = CreateCheckboxGrid(inner, menuDisplayOptions, cy, iw)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_VAULT_LOOK"]) or "Look & Opacity",
            iw, cy, {})
        cy = CreateSliderWidget(inner, {
            name = (ns.L and ns.L["CONFIG_VAULT_BUTTON_OPACITY"]) or "Button Opacity",
            desc = (ns.L and ns.L["CONFIG_VAULT_BUTTON_OPACITY_DESC"]) or "Adjust Easy Access opacity when it is visible.",
            min = 0.2,
            max = 1.0,
            step = 0.05,
            get = function() return GetVaultButtonSettings().opacity or 1.0 end,
            set = function(_, value)
                value = math.floor(value * 20 + 0.5) / 20
                GetVaultButtonSettings().opacity = value
                RefreshVaultButton()
            end,
            valueFormat = function(v) return string.format("%d%%", v * 100) end,
        }, cy, sliderElements)
        return cy
    end, { flat = true, noTrailingGap = true })

    local vaultContentHeight = SettingsMeasuredSectionContentHeight(vaultStackY)
    FinalizeSettingsSectionHeight(vaultSection, vaultContentHeight, false)

    yOffset = yOffset - vaultSection:GetHeight() - SETTINGS_SECTION_GAP
    return yOffset
end
