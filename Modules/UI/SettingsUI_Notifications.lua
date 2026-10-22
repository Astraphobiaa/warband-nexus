--[[
    Warband Nexus - Settings UI notifications panel (alerts, position, try counter chat).
    Split from SettingsUI.lua (BuildSettings panel body; file size / Lua 5.1 limits).
    Loaded after Modules/UI/SettingsUI.lua: helpers come from ns.SettingsUI._H at call time.
]]

local ADDON_NAME, ns = ...
local M = ns.SettingsUI
assert(M and M._H, "SettingsUI_Notifications.lua loaded before SettingsUI.lua - check the TOC")

---@param ctx table `{ parent, effectiveWidth, sideInset, yOffset, skipPanelIntro, AnchorSectionTop }`
---@return number yOffset
function M.AppendNotificationsPanel(ctx)
    local H = M._H
    local WarbandNexus = H.WarbandNexus
    local COLORS = H.COLORS
    local FontManager = H.FontManager
    local ns = H.ns
    local issecretvalue = H.issecretvalue
    local SETTINGS_SECTION_GAP = H.SETTINGS_SECTION_GAP
    local SETTINGS_COMPACT_BTN_H = H.SETTINGS_COMPACT_BTN_H
    local SETTINGS_ANCHOR_DESC_MIN_HEIGHT = H.SETTINGS_ANCHOR_DESC_MIN_HEIGHT
    local UI_SPACING = H.UI_SPACING
    local GetSettingsSectionContentWidth = H.GetSettingsSectionContentWidth
    local GetHeaderToolbarGap = H.GetHeaderToolbarGap
    local AppendSettingsPanelIntro = H.AppendSettingsPanelIntro
    local AppendSettingsSubSectionHeader = H.AppendSettingsSubSectionHeader
    local StackSettingsSubPanel = H.StackSettingsSubPanel
    local CreateSection = H.CreateSection
    local CreateCheckboxGrid = H.CreateCheckboxGrid
    local CreateDropdownWidget = H.CreateDropdownWidget
    local CreateSliderWidget = H.CreateSliderWidget
    local CreateThemedCheckbox = H.CreateThemedCheckbox
    local FinalizeSettingsSectionHeight = H.FinalizeSettingsSectionHeight
    local SettingsMeasuredSectionContentHeight = H.SettingsMeasuredSectionContentHeight
    local ApplySettingsChrome = H.ApplySettingsChrome
    local ApplySettingsAccentChromeIdle = H.ApplySettingsAccentChromeIdle
    local WireSettingsAccentButtonHover = H.WireSettingsAccentButtonHover
    local RegisterSettingsAccentChrome = H.RegisterSettingsAccentChrome
    local SettingsControlChromeHover = H.SettingsControlChromeHover
    local SettingsDialogShellBg = H.SettingsDialogShellBg
    local Settings_ShowWrappedTooltip = H.Settings_ShowWrappedTooltip
    local SetCheckboxDisabled = H.SetCheckboxDisabled
    local sliderElements = H.sliderElements
    local parent = ctx.parent
    local effectiveWidth = ctx.effectiveWidth
    local sideInset = ctx.sideInset
    local yOffset = ctx.yOffset
    local skipPanelIntro = ctx.skipPanelIntro
    local AnchorSectionTop = ctx.AnchorSectionTop

    -- NOTIFICATIONS
    yOffset = AppendSettingsPanelIntro(parent, "notifications", effectiveWidth, yOffset, sideInset, skipPanelIntro)
    local notifSection = CreateSection(parent, nil, effectiveWidth)
    AnchorSectionTop(notifSection, yOffset)

    local notifGridOpts = {
        indentChildren = true,
        minColumns = 2,
        maxColumns = 3,
        minColWidth = 220,
        childIndent = 14,
    }

    local notifMasterOptions = {
        {
            key = "enabled",
            label = (ns.L and ns.L["ENABLE_NOTIFICATIONS"]) or "Enable All Notifications",
            tooltip = (ns.L and ns.L["ENABLE_NOTIFICATIONS_TOOLTIP"]) or "Master toggle — disables all popup notifications, chat alerts, and visual effects below",
            get = function() return WarbandNexus.db.profile.notifications.enabled end,
            set = function(value)
                WarbandNexus.db.profile.notifications.enabled = value
                -- Master toggle affects Blizzard message suppression/restoration
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
                if WarbandNexus.ApplyBlizzardAchievementAlertSuppression then
                    WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
                end
            end,
        },
        {
            key = "vault",
            parentKey = "enabled",
            label = (ns.L and ns.L["VAULT_REMINDER"]) or "Weekly Vault Reminder",
            tooltip = (ns.L and ns.L["VAULT_REMINDER_TOOLTIP"]) or "Show a reminder popup on login when you have unclaimed Great Vault rewards",
            get = function() return WarbandNexus.db.profile.notifications.showVaultReminder end,
            set = function(value) WarbandNexus.db.profile.notifications.showVaultReminder = value end,
        },
        {
            key = "mailReminder",
            parentKey = "enabled",
            label = (ns.L and ns.L["MAIL_REMINDER"]) or "Mail Expiry Reminder",
            tooltip = (ns.L and ns.L["MAIL_REMINDER_TOOLTIP"]) or "Show a reminder popup on login when mail on any tracked character expires within a week. The envelope icon on the Characters tab turns orange in the last week and red in the last day.",
            get = function() return WarbandNexus.db.profile.notifications.showMailReminder ~= false end,
            set = function(value) WarbandNexus.db.profile.notifications.showMailReminder = value end,
        },
        {
            key = "planReminderToast",
            parentKey = "enabled",
            label = (ns.L and ns.L["CONFIG_PLAN_REMINDER_TOAST"]) or "To-Do reminder popups",
            tooltip = (ns.L and ns.L["CONFIG_PLAN_REMINDER_TOAST_DESC"]) or "Show a compact toast when a plan reminder fires (daily login, monthly login, weekly reset, zone or instance enter, etc.). Plan cards still show the horn badge.",
            get = function() return WarbandNexus.db.profile.notifications.showPlanReminderToast ~= false end,
            set = function(value) WarbandNexus.db.profile.notifications.showPlanReminderToast = value end,
        },
        {
            key = "updateNotes",
            parentKey = "enabled",
            label = (ns.L and ns.L["CONFIG_SHOW_UPDATE_NOTES"]) or "Show Update Notes",
            tooltip = (ns.L and ns.L["CONFIG_SHOW_UPDATE_NOTES_DESC"]) or "Display the What's New window on next login.",
            get = function() return WarbandNexus.db.profile.notifications.showUpdateNotes end,
            set = function(value) WarbandNexus.db.profile.notifications.showUpdateNotes = value end,
        },
    }

    local notifAchievementOptions = {
        {
            key = "hideBlizzAchievement",
            parentKey = "enabled",
            skipChildSync = true,
            hideChildrenWhenOff = true,
            label = (ns.L and ns.L["HIDE_BLIZZARD_ACHIEVEMENT"]) or "Warband achievement popups",
            tooltip = (ns.L and ns.L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"])
                or "On: Warband Nexus shows achievement earned and criteria-step toasts. Off: Blizzard's default gold achievement alerts.",
            get = function() return WarbandNexus.db.profile.notifications.hideBlizzardAchievementAlert end,
            set = function(value)
                WarbandNexus.db.profile.notifications.hideBlizzardAchievementAlert = value
                if WarbandNexus.ApplyBlizzardAchievementAlertSuppression then
                    WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
                end
            end,
        },
        {
            key = "lootAchievement",
            parentKey = "hideBlizzAchievement",
            label = (ns.L and ns.L["LOOT_ALERTS_ACHIEVEMENT"]) or "Earned achievement popup",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_ACHIEVEMENT_TOOLTIP"])
                or "Large popup when the whole achievement is earned (Warband popups must be on).",
            get = function() return WarbandNexus.db.profile.notifications.showAchievementNotifications end,
            set = function(value)
                WarbandNexus.db.profile.notifications.showAchievementNotifications = value
                if WarbandNexus.ApplyBlizzardAchievementAlertSuppression then
                    WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
                end
            end,
        },
        {
            key = "showCriteriaProgress",
            parentKey = "hideBlizzAchievement",
            label = (ns.L and ns.L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS"]) or "Criteria progress popup",
            tooltip = (ns.L and ns.L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS_TOOLTIP"])
                or "Small toast each time one step completes (Traveler's Log, treasures, etc.). Off: Blizzard criteria bar.",
            get = function() return WarbandNexus.db.profile.notifications.showCriteriaProgressNotifications end,
            set = function(value)
                WarbandNexus.db.profile.notifications.showCriteriaProgressNotifications = value
                if WarbandNexus.ApplyBlizzardAchievementAlertSuppression then
                    WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
                end
            end,
        },
    }

    local notifCollectibleOptions = {
        {
            key = "loot",
            parentKey = "enabled",
            label = (ns.L and ns.L["LOOT_ALERTS"]) or "Collectible popups",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_TOOLTIP"]) or "Master switch for mount, pet, toy, and appearance drop popups.",
            get = function() return WarbandNexus.db.profile.notifications.showLootNotifications end,
            set = function(value)
                WarbandNexus.db.profile.notifications.showLootNotifications = value
                if WarbandNexus.ApplyBlizzardAchievementAlertSuppression then
                    WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
                end
            end,
        },
        {
            key = "lootMount",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_MOUNT"]) or "Mounts",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_MOUNT_TOOLTIP"]) or "Popup when you learn a new mount.",
            get = function() return WarbandNexus.db.profile.notifications.showMountNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showMountNotifications = value end,
        },
        {
            key = "lootPet",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_PET"]) or "Pets",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_PET_TOOLTIP"]) or "Popup when you learn a new battle pet.",
            get = function() return WarbandNexus.db.profile.notifications.showPetNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showPetNotifications = value end,
        },
        {
            key = "lootToy",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_TOY"]) or "Toys",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_TOY_TOOLTIP"]) or "Popup when you learn a new toy.",
            get = function() return WarbandNexus.db.profile.notifications.showToyNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showToyNotifications = value end,
        },
        {
            key = "lootIllusion",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_ILLUSION"]) or "Illusions",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_ILLUSION_TOOLTIP"]) or "Popup when you unlock a new weapon illusion.",
            get = function() return WarbandNexus.db.profile.notifications.showIllusionNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showIllusionNotifications = value end,
        },
        {
            key = "lootTitle",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_TITLE"]) or "Titles",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_TITLE_TOOLTIP"]) or "Popup when you earn a new title.",
            get = function() return WarbandNexus.db.profile.notifications.showTitleNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showTitleNotifications = value end,
        },
    }

    local notifChatOptions = {
        {
            key = "loginChat",
            parentKey = "enabled",
            label = (ns.L and ns.L["CONFIG_SHOW_LOGIN_CHAT"]) or "Login message in chat",
            tooltip = (ns.L and ns.L["CONFIG_SHOW_LOGIN_CHAT_DESC"]) or "Short welcome line in chat on login (separate from the What's New window).",
            get = function() return WarbandNexus.db.profile.notifications.showLoginChat ~= false end,
            set = function(value) WarbandNexus.db.profile.notifications.showLoginChat = value end,
        },
        {
            key = "hidePlayedTime",
            parentKey = "enabled",
            label = (ns.L and ns.L["CONFIG_HIDE_PLAYED_TIME_CHAT"]) or "Hide time played in chat",
            tooltip = (ns.L and ns.L["CONFIG_HIDE_PLAYED_TIME_CHAT_DESC"]) or "Filter Total time played and Time played this level system messages.",
            get = function() return WarbandNexus.db.profile.notifications.hidePlayedTimeInChat ~= false end,
            set = function(value)
                WarbandNexus.db.profile.notifications.hidePlayedTimeInChat = value
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
            end,
        },
        {
            key = "reputation",
            parentKey = "enabled",
            label = (ns.L and ns.L["REPUTATION_GAINS"]) or "Rep Gains in Chat",
            tooltip = (ns.L and ns.L["REPUTATION_GAINS_TOOLTIP"]) or "Display reputation gain messages in chat when you earn faction standing",
            get = function() return WarbandNexus.db.profile.notifications.showReputationGains end,
            set = function(value)
                WarbandNexus.db.profile.notifications.showReputationGains = value
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
            end,
        },
        {
            key = "currency",
            parentKey = "enabled",
            label = (ns.L and ns.L["CURRENCY_GAINS"]) or "Currency Gains in Chat",
            tooltip = (ns.L and ns.L["CURRENCY_GAINS_TOOLTIP"]) or "Display currency gain messages in chat when you earn currencies",
            get = function() return WarbandNexus.db.profile.notifications.showCurrencyGains end,
            set = function(value)
                WarbandNexus.db.profile.notifications.showCurrencyGains = value
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
            end,
        },
    }

    local notifTryOptions = {
        {
            key = "autoTryCounter",
            parentKey = "enabled",
            label = (ns.L and ns.L["AUTO_TRY_COUNTER"]) or "Track drop attempts",
            tooltip = (ns.L and ns.L["AUTO_TRY_COUNTER_TOOLTIP"])
                or "Count failed kills, opens, and casts toward mounts, pets, toys, and illusions. Shows attempt total on the drop popup.",
            get = function() return WarbandNexus.db.profile.notifications.autoTryCounter end,
            set = function(value) WarbandNexus.db.profile.notifications.autoTryCounter = value end,
        },
        {
            key = "syncTryCountDownToStatistics",
            parentKey = "autoTryCounter",
            label = (ns.L and ns.L["SYNC_TRY_COUNT_DOWN_TO_STATISTICS"]) or "Match Statistics downward",
            tooltip = (ns.L and ns.L["SYNC_TRY_COUNT_DOWN_TO_STATISTICS_TOOLTIP"])
                or "When enabled, stat-backed mounts can decrease to match WoW Statistics totals on login or /wn tc sync-stats. Default off (only raises counts).",
            get = function() return WarbandNexus.db.profile.notifications.syncTryCountDownToStatistics == true end,
            set = function(value) WarbandNexus.db.profile.notifications.syncTryCountDownToStatistics = value end,
        },
        {
            key = "hideTryCounterChat",
            parentKey = "autoTryCounter",
            label = (ns.L and ns.L["HIDE_TRY_COUNTER_CHAT"]) or "Hide try lines in chat",
            tooltip = (ns.L and ns.L["HIDE_TRY_COUNTER_CHAT_TOOLTIP"])
                or "Suppress all try counter messages in chat ([WN-Counter], [WN-Drops], obtained/caught lines). Counting continues normally — only chat output is hidden.",
            get = function() return WarbandNexus.db.profile.notifications.hideTryCounterChat == true end,
            set = function(value) WarbandNexus.db.profile.notifications.hideTryCounterChat = value end,
        },
        {
            key = "tryCounterInstanceEntryDropLines",
            parentKey = "autoTryCounter",
            label = (ns.L and ns.L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES"]) or "List drops on instance enter",
            tooltip = (ns.L and ns.L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES_TOOLTIP"])
                or "Print [WN-Drops] lines on dungeon/raid entry with difficulty colors vs your current instance, or turn off for a one-line hint only.",
            get = function()
                local v = WarbandNexus.db.profile.notifications.tryCounterInstanceEntryDropLines
                if v == false then return false end
                return true
            end,
            set = function(value) WarbandNexus.db.profile.notifications.tryCounterInstanceEntryDropLines = value end,
        },
        {
            key = "screenFlash",
            parentKey = "autoTryCounter",
            label = (ns.L and ns.L["SCREEN_FLASH_EFFECT"]) or "Screen flash on drop",
            tooltip = (ns.L and ns.L["SCREEN_FLASH_EFFECT_TOOLTIP"]) or "Play a screen flash animation when you finally obtain a collectible after multiple farming attempts",
            get = function() return WarbandNexus.db.profile.notifications.screenFlashEffect end,
            set = function(value) WarbandNexus.db.profile.notifications.screenFlashEffect = value end,
        },
        {
            key = "tryCounterDropScreenshot",
            parentKey = "autoTryCounter",
            label = (ns.L and ns.L["TRY_COUNTER_DROP_SCREENSHOT"]) or "Screenshot on drop",
            tooltip = (ns.L and ns.L["TRY_COUNTER_DROP_SCREENSHOT_TOOLTIP"])
                or "When a mount, pet, toy, or illusion you were try-tracking finally drops, take an automatic screenshot (~0.3s after the popup). Independent of the screen flash option.",
            get = function() return WarbandNexus.db.profile.notifications.tryCounterDropScreenshot ~= false end,
            set = function(value) WarbandNexus.db.profile.notifications.tryCounterDropScreenshot = value end,
        },
    }

    local notifInnerW = GetSettingsSectionContentWidth(effectiveWidth)
    local notifStackY = 0
    local notifWidgets = {}
    local notifGridOptsWithRegistry = {}
    for k, v in pairs(notifGridOpts) do
        notifGridOptsWithRegistry[k] = v
    end
    notifGridOptsWithRegistry.externalWidgets = notifWidgets
    local tcChatRouteDropdown, tcChatRouteLabel
    local addTcChatBtn

    local function MergeCheckboxWidgets(into, from)
        if not into or not from then return end
        for k, v in pairs(from) do
            into[k] = v
        end
    end

    notifStackY = StackSettingsSubPanel(notifSection.content, notifInnerW, 0, function(inner, iw)
        local cy = 0
        local w
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_NOTIF_MASTER"]) or "General",
            iw, cy, { skipGapBefore = true })
        cy, w = CreateCheckboxGrid(inner, notifMasterOptions, cy, iw, notifGridOptsWithRegistry)
        MergeCheckboxWidgets(notifWidgets, w)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_NOTIF_ACHIEVEMENTS"]) or "Achievement popups",
            iw, cy, {})
        cy, w = CreateCheckboxGrid(inner, notifAchievementOptions, cy, iw, notifGridOptsWithRegistry)
        MergeCheckboxWidgets(notifWidgets, w)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_NOTIF_COLLECTIBLES"]) or "Collectible popups",
            iw, cy, {})
        cy, w = CreateCheckboxGrid(inner, notifCollectibleOptions, cy, iw, notifGridOptsWithRegistry)
        MergeCheckboxWidgets(notifWidgets, w)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_NOTIF_CHAT"]) or "Chat filters",
            iw, cy, {})
        cy, w = CreateCheckboxGrid(inner, notifChatOptions, cy, iw, notifGridOptsWithRegistry)
        MergeCheckboxWidgets(notifWidgets, w)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_NOTIF_TRY_COUNTER"]) or "Try counter",
            iw, cy, {})
        cy, w = CreateCheckboxGrid(inner, notifTryOptions, cy, iw, notifGridOptsWithRegistry)
        MergeCheckboxWidgets(notifWidgets, w)

        cy = cy - GetHeaderToolbarGap()
        cy, tcChatRouteDropdown, tcChatRouteLabel = CreateDropdownWidget(inner, {
            stackBelowLabel = true,
            name = (ns.L and ns.L["TRYCOUNTER_CHAT_ROUTE_LABEL"]) or "Try counter chat output",
            desc = (ns.L and ns.L["TRYCOUNTER_CHAT_ROUTE_DESC"])
                or "Default uses the same tabs as Loot messages. “Warband Nexus” is a separate filter you can enable per tab (often listed in the chat tab settings). “All tabs” prints to every standard chat window.",
            menuOpensUpward = false,
            valueOrder = { "loot", "dedicated", "all_tabs" },
            values = {
                loot = (ns.L and ns.L["TRYCOUNTER_CHAT_ROUTE_LOOT"]) or "1) Same tabs as Loot (default)",
                dedicated = (ns.L and ns.L["TRYCOUNTER_CHAT_ROUTE_DEDICATED"]) or "2) Warband Nexus (separate filter)",
                all_tabs = (ns.L and ns.L["TRYCOUNTER_CHAT_ROUTE_ALL_TABS"]) or "3) All standard chat tabs",
            },
            get = function()
                return WarbandNexus.db.profile.notifications.tryCounterChatRoute or "loot"
            end,
            set = function(_, value)
                WarbandNexus.db.profile.notifications.tryCounterChatRoute = value
                if ns.ChatOutput and ns.ChatOutput.OnTryCounterChatRouteChanged then
                    ns.ChatOutput.OnTryCounterChatRouteChanged(value)
                end
            end,
        }, cy)
        cy = cy - GetHeaderToolbarGap()
        addTcChatBtn = ns.UI.Factory:CreateButton(inner)
        addTcChatBtn:SetSize(math.min(iw, 320), SETTINGS_COMPACT_BTN_H)
        addTcChatBtn:SetPoint("TOPLEFT", 0, cy)
        local addTcChatBtnText = addTcChatBtn:GetFontString() or FontManager:CreateFontString(addTcChatBtn, "body", "OVERLAY")
        addTcChatBtnText:SetPoint("CENTER")
        addTcChatBtnText:SetText((ns.L and ns.L["TRYCOUNTER_CHAT_ADD_TO_TAB_BTN"]) or "Add try counter to selected chat tab")
        addTcChatBtn:SetFontString(addTcChatBtnText)
        ApplySettingsAccentChromeIdle(addTcChatBtn)
        RegisterSettingsAccentChrome(addTcChatBtn)
        addTcChatBtn:SetScript("OnEnter", function(self)
            if ApplySettingsChrome then
                local C = ns.UI_COLORS or COLORS
                local a = C.accent or COLORS.accent
                ApplySettingsChrome(self, SettingsControlChromeHover(), { a[1], a[2], a[3], 1 })
            end
            Settings_ShowWrappedTooltip(self, (ns.L and ns.L["TRYCOUNTER_CHAT_ADD_TO_TAB_TOOLTIP"])
                or "Select the chat tab you want, then click. Use with “Warband Nexus (separate filter)” mode so try lines are not tied to Loot.")
        end)
        addTcChatBtn:SetScript("OnLeave", function(self)
            ApplySettingsAccentChromeIdle(self)
            GameTooltip:Hide()
        end)
        addTcChatBtn:SetScript("OnClick", function()
            if ns.ChatOutput and ns.ChatOutput.AddTryCounterGroupToSelectedChatFrame then
                local ok, err = ns.ChatOutput.AddTryCounterGroupToSelectedChatFrame()
                if ok and WarbandNexus.Print then
                    WarbandNexus:Print((ns.L and ns.L["TRYCOUNTER_CHAT_ADD_TO_TAB_OK"]) or "|cff9966ff[Warband Nexus]|r Try counter enabled on the selected chat tab.")
                elseif WarbandNexus.Print then
                    WarbandNexus:Print((ns.L and ns.L["TRYCOUNTER_CHAT_ADD_TO_TAB_FAIL"]) or "|cffff6600[Warband Nexus]|r Could not update the chat tab (no chat frame or API blocked).")
                end
            end
        end)
        local btnTrail = GetHeaderToolbarGap()
        return cy - SETTINGS_COMPACT_BTN_H - btnTrail
    end, { flat = true, noTrailingGap = true })

    local notifGridYOffset = notifStackY

    -- Track external dependents (sliders, buttons) that should disable when notifications are OFF
    local notifExternalDependents = {}

    -- Chat-dependent widgets: disabled when hideTryCounterChat is checked OR autoTryCounter is off
    local tcChatDependents = { tcChatRouteDropdown, tcChatRouteLabel, addTcChatBtn }
    local function ApplyHideTryCounterChatCascade()
        local chatHidden = WarbandNexus.db and WarbandNexus.db.profile
            and WarbandNexus.db.profile.notifications
            and WarbandNexus.db.profile.notifications.hideTryCounterChat
        local autoOff = not (WarbandNexus.db and WarbandNexus.db.profile
            and WarbandNexus.db.profile.notifications
            and WarbandNexus.db.profile.notifications.autoTryCounter)
        local shouldDisable = chatHidden or autoOff
        for wi = 1, #tcChatDependents do
            local w = tcChatDependents[wi]
            if w then
                if shouldDisable then
                    if w.Disable then w:Disable() end
                    w:SetAlpha(0.35)
                else
                    if w.Enable then w:Enable() end
                    w:SetAlpha(1.0)
                end
            end
        end
        local entryW = notifWidgets["tryCounterInstanceEntryDropLines"]
        if entryW then
            SetCheckboxDisabled(entryW.checkbox, entryW.label, shouldDisable)
        end
    end

    notifWidgets._onParentToggle = function(key, isEnabled)
        if key == "enabled" then
            for di = 1, #notifExternalDependents do
                local dep = notifExternalDependents[di]
                if dep.type == "slider" then
                    if isEnabled then
                        dep.widget:Enable()
                        dep.widget:SetAlpha(1.0)
                        if dep.label then dep.label:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]) end
                        if dep.valueLabel then ns.UI_SetTextColorRole(dep.valueLabel, "Bright") end
                    else
                        dep.widget:Disable()
                        dep.widget:SetAlpha(0.35)
                        if dep.label then ns.UI_SetTextColorRole(dep.label, "Dim", 0.6) end
                        if dep.valueLabel then ns.UI_SetTextColorRole(dep.valueLabel, "Dim", 0.6) end
                    end
                elseif dep.type == "button" then
                    if isEnabled then
                        dep.widget:Enable()
                        dep.widget:SetAlpha(1.0)
                    else
                        dep.widget:Disable()
                        dep.widget:SetAlpha(0.35)
                    end
                elseif dep.type == "label" then
                    if isEnabled then
                        -- Role / accent resolved at call time; build-time copies went stale on
                        -- theme or accent change (2026-10-22).
                        if dep.role then
                            ns.UI_SetTextColorRole(dep.widget, dep.role)
                        else
                            dep.widget:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
                        end
                    else
                        ns.UI_SetTextColorRole(dep.widget, "Dim", 0.6)
                    end
                end
            end
        end
        if key == "hideTryCounterChat" or key == "autoTryCounter" then
            ApplyHideTryCounterChatCascade()
        end
    end
    ApplyHideTryCounterChatCascade()

    -- ---- Notification Duration ----
    notifGridYOffset = notifGridYOffset - GetHeaderToolbarGap()
    local durationLabel
    notifGridYOffset, durationLabel = AppendSettingsSubSectionHeader(notifSection.content,
        (ns.L and ns.L["SETTINGS_SECTION_NOTIF_TIMING"]) or "Timing",
        notifInnerW, notifGridYOffset, { skipGapAfter = true })
    notifGridYOffset = notifGridYOffset - math.floor(GetHeaderToolbarGap() * 0.5 + 0.5)

    local durationSlider = nil  -- Will capture from sliderElements
    local sliderCountBefore = #sliderElements
    notifGridYOffset = CreateSliderWidget(notifSection.content, {
        name = (ns.L and ns.L["DURATION_LABEL"]) or "Duration",
        min = 3,
        max = 15,
        step = 1,
        valueFormat = function(v) return tostring(math.floor(v + 0.5)) .. "s" end,
        get = function() return WarbandNexus.db.profile.notifications.popupDuration or 5 end,
        set = function(_, value)
            value = math.floor(value + 0.5)
            WarbandNexus.db.profile.notifications.popupDuration = value
        end,
    }, notifGridYOffset, sliderElements)
    -- Capture the just-created slider for dependency tracking
    if #sliderElements > sliderCountBefore then
        durationSlider = sliderElements[#sliderElements]
    end
    
    -- ---- Notification position ----
    notifGridYOffset = notifGridYOffset - GetHeaderToolbarGap()
    notifGridYOffset = AppendSettingsSubSectionHeader(notifSection.content,
        (ns.L and ns.L["SETTINGS_SECTION_NOTIF_POSITION"]) or "Popup position",
        notifInnerW, notifGridYOffset, { skipGapAfter = true })
    notifGridYOffset = notifGridYOffset - math.floor(GetHeaderToolbarGap() * 0.5 + 0.5)

    local setPosBtn, resetBtn, testBtn
    local useAlertFrameCheck
    local unifiedLayoutCheck
    local lanePosButtons = {}
    local notifPerLaneLabel
    local RefreshNotifAnchorControlsVisibility

    local function SyncLegacyReminderToastFromProgressLane(db)
        if not db then return end
        local pt = db.popupPoint or "TOP"
        local x = db.popupX or 0
        local y = db.popupY or -100
        db.reminderToastPoint = pt
        db.reminderToastX = x
        db.reminderToastY = y
        db.popupPointCompact = pt
        db.popupXCompact = x
        db.popupYCompact = y
        db.reminderToastUseCriteriaLane = true
    end

    local function NotificationPositionGhostBlocked()
        if not InCombatLockdown() then return false end
        if WarbandNexus and WarbandNexus.Print then
            local msg = (ns.L and ns.L["SETTINGS_NOTIF_POSITION_COMBAT"]) or "Cannot position notification previews during combat."
            WarbandNexus:Print("|cffff6600[Warband Nexus]|r " .. msg .. "|r")
        end
        return true
    end

    local function ApplyNotificationAnchorForLane(lane, anchorPoint, offsetX, offsetY)
        local db = WarbandNexus.db.profile.notifications
        if lane == "achievement" then
            db.popupPoint = anchorPoint
            db.popupX = offsetX
            db.popupY = offsetY
            db.useAlertFramePosition = false
            if useAlertFrameCheck then
                useAlertFrameCheck:SetChecked(false)
                if useAlertFrameCheck.checkTexture then useAlertFrameCheck.checkTexture:SetShown(false) end
            end
        elseif lane == "criteria" then
            db.popupPointCompact = anchorPoint
            db.popupXCompact = offsetX
            db.popupYCompact = offsetY
            db.useCriteriaAlertFramePosition = false
        elseif lane == "tryCounter" then
            db.tryCounterToastPoint = anchorPoint
            db.tryCounterToastX = offsetX
            db.tryCounterToastY = offsetY
        elseif lane == "reminder" then
            db.reminderToastPoint = anchorPoint
            db.reminderToastX = offsetX
            db.reminderToastY = offsetY
            db.reminderToastUseCriteriaLane = false
        end
    end

    local function ApplyNotificationOffsetsToDb(anchorPoint, offsetX, offsetY)
        local db = WarbandNexus.db.profile.notifications
        db.popupPoint = anchorPoint
        db.popupX = offsetX
        db.popupY = offsetY
        db.popupPointCompact = anchorPoint
        db.popupXCompact = offsetX
        db.popupYCompact = offsetY
        db.useAlertFramePosition = false
        db.unifiedToastLayout = true
        SyncLegacyReminderToastFromProgressLane(db)
        if useAlertFrameCheck then
            useAlertFrameCheck:SetChecked(false)
            if useAlertFrameCheck.checkTexture then useAlertFrameCheck.checkTexture:SetShown(false) end
        end
    end

    local function ComputeAnchorOffsetsFromGhost(ghost)
        ghost:StopMovingOrSizing()
        local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
        local left, top = ghost:GetLeft(), ghost:GetTop()
        local w = ghost:GetWidth()
        local centerX = left + (w / 2)
        local centerY = top - (ghost:GetHeight() / 2)
        local anchorPoint, offsetX, offsetY
        if centerY > (screenH * 0.6) then
            anchorPoint = "TOP"
            offsetX = math.floor(centerX - (screenW / 2))
            offsetY = math.floor(top - screenH)
        elseif centerY < (screenH * 0.4) then
            anchorPoint = "BOTTOM"
            offsetX = math.floor(centerX - (screenW / 2))
            offsetY = math.floor(top - ghost:GetHeight())
        else
            anchorPoint = "CENTER"
            offsetX = math.floor(centerX - (screenW / 2))
            offsetY = math.floor(centerY - (screenH / 2))
        end
        return anchorPoint, offsetX, offsetY
    end

    local function CloseNotificationCoordDialog()
        local d = WarbandNexus._notifCoordDialog
        if d then
            d:Hide()
            if ns.UI_UnregisterScaledFrame then ns.UI_UnregisterScaledFrame(d) end
            WarbandNexus._notifCoordDialog = nil
        end
    end

    local function ShowNotificationCoordDialog(holder)
        if not holder then return end
        CloseNotificationCoordDialog()
        local dlgW, dlgH = 340, 236
        local dlg = ns.UI.Factory:CreateContainer(UIParent, dlgW, dlgH, true)
        if not dlg then return end
        dlg:SetFrameStrata("DIALOG")
        dlg:SetFrameLevel(2100)
        if ApplySettingsChrome then ApplySettingsChrome(dlg, SettingsDialogShellBg(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.88 }) end
        WarbandNexus._notifCoordDialog = dlg

        local cy = -14
        local title = FontManager:CreateFontString(dlg, "body", "OVERLAY")
        title:SetPoint("TOPLEFT", 14, cy)
        title:SetPoint("TOPRIGHT", -14, cy)
        title:SetJustifyH("LEFT")
        title:SetText((ns.L and ns.L["SETTINGS_NOTIF_COORD_TITLE"]) or "Notification position (pixels)")
        ns.UI_SetTextColorRole(title, "Bright")
        cy = cy - math.max(22, title:GetStringHeight()) - 10

        local anchLbl = FontManager:CreateFontString(dlg, "body", "OVERLAY")
        anchLbl:SetPoint("TOPLEFT", 14, cy)
        anchLbl:SetText((ns.L and ns.L["SETTINGS_NOTIF_COORD_ANCHOR"]) or "Anchor")
        ns.UI_SetTextColorRole(anchLbl, "Normal")

        dlg.selectedAnchor = "TOP"
        local anchorBtns = {}
        local function UpdateAnchorButtonVisuals()
            for ap, btn in pairs(anchorBtns) do
                local sel = (dlg.selectedAnchor == ap)
                if btn._wnBlizzardButton and ns.UI_ApplyClassicNavTabActiveState then
                    ns.UI_ApplyClassicNavTabActiveState(btn, sel)
                elseif sel then
                    local listenBg = ns.UI_GetAccentListeningBackdrop and ns.UI_GetAccentListeningBackdrop() or SettingsControlChromeHover()
                    ApplySettingsChrome(btn, listenBg, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.95 })
                else
                    ApplySettingsAccentChromeIdle(btn)
                end
            end
        end

        local abW, abGap = 72, 8
        local apOrder = { "TOP", "BOTTOM", "CENTER" }
        for i = 1, #apOrder do
            local ap = apOrder[i]
            local ab = ns.UI.Factory:CreateButton(dlg)
            ab:SetSize(abW, SETTINGS_COMPACT_BTN_H - 2)
            ab:SetPoint("TOPLEFT", dlg, "TOPLEFT", 96 + (i - 1) * (abW + abGap), cy - 2)
            local abText = ab:GetFontString() or FontManager:CreateFontString(ab, "body", "OVERLAY")
            abText:SetPoint("CENTER")
            abText:SetText(ap)
            ns.UI_SetTextColorRole(abText, "Bright")
            ab:SetFontString(abText)
            ApplySettingsAccentChromeIdle(ab)
            WireSettingsAccentButtonHover(ab)
            RegisterSettingsAccentChrome(ab)
            anchorBtns[ap] = ab
        end
        cy = cy - SETTINGS_COMPACT_BTN_H - 14

        local xLbl = FontManager:CreateFontString(dlg, "body", "OVERLAY")
        xLbl:SetPoint("TOPLEFT", 14, cy)
        xLbl:SetText((ns.L and ns.L["SETTINGS_NOTIF_COORD_X"]) or "X offset")
        ns.UI_SetTextColorRole(xLbl, "Normal")
        local xBox = ns.UI.Factory:CreateEditBox(dlg)
        xBox:SetSize(160, 28)
        xBox:SetPoint("TOPLEFT", dlg, "TOPLEFT", 140, cy - 2)
        xBox:SetTextInsets(8, 8, 0, 0)
        ApplySettingsAccentChromeIdle(xBox)
        WireSettingsAccentButtonHover(xBox)
        RegisterSettingsAccentChrome(xBox)
        cy = cy - 36

        local yLbl = FontManager:CreateFontString(dlg, "body", "OVERLAY")
        yLbl:SetPoint("TOPLEFT", 14, cy)
        yLbl:SetText((ns.L and ns.L["SETTINGS_NOTIF_COORD_Y"]) or "Y offset")
        ns.UI_SetTextColorRole(yLbl, "Normal")
        local yBox = ns.UI.Factory:CreateEditBox(dlg)
        yBox:SetSize(160, 28)
        yBox:SetPoint("TOPLEFT", dlg, "TOPLEFT", 140, cy - 2)
        yBox:SetTextInsets(8, 8, 0, 0)
        ApplySettingsAccentChromeIdle(yBox)
        WireSettingsAccentButtonHover(yBox)
        RegisterSettingsAccentChrome(yBox)

        ---@return boolean committed When false (e.g. secret text), DB was not updated.
        local function ApplyFromDialog()
            local xt = xBox:GetText()
            local yt = yBox:GetText()
            if xt and issecretvalue and issecretvalue(xt) then return false end
            if yt and issecretvalue and issecretvalue(yt) then return false end
            local x = tonumber(xt)
            local y = tonumber(yt)
            if not x then x = 0 end
            if not y then y = 0 end
            x = math.floor(x + 0.5)
            y = math.floor(y + 0.5)
            local pt = dlg.selectedAnchor or "TOP"
            local lane = WarbandNexus._notifGhostLane
            if lane then
                ApplyNotificationAnchorForLane(lane, pt, x, y)
            else
                ApplyNotificationOffsetsToDb(pt, x, y)
            end
            holder:ClearAllPoints()
            holder:SetPoint(pt, UIParent, pt, x, y)
            return true
        end

        for _, ap in ipairs(apOrder) do
            anchorBtns[ap]:SetScript("OnClick", function()
                dlg.selectedAnchor = ap
                UpdateAnchorButtonVisuals()
                ApplyFromDialog()
            end)
        end

        xBox:SetScript("OnEnterPressed", function(self)
            if ApplyFromDialog() then
                WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_SAVED_MSG"]) or "Position saved!") .. "|r")
            end
            self:ClearFocus()
        end)
        xBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        yBox:SetScript("OnEnterPressed", function(self)
            if ApplyFromDialog() then
                WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_SAVED_MSG"]) or "Position saved!") .. "|r")
            end
            self:ClearFocus()
        end)
        yBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local applyBtn = ns.UI.Factory:CreateButton(dlg)
        applyBtn:SetSize(100, SETTINGS_COMPACT_BTN_H - 2)
        applyBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 12)
        local applyBtnText = applyBtn:GetFontString() or FontManager:CreateFontString(applyBtn, "body", "OVERLAY")
        applyBtnText:SetPoint("CENTER")
        applyBtnText:SetText((ns.L and ns.L["SETTINGS_NOTIF_COORD_APPLY"]) or "Apply")
        applyBtn:SetFontString(applyBtnText)
        ApplySettingsAccentChromeIdle(applyBtn)
        WireSettingsAccentButtonHover(applyBtn)
        RegisterSettingsAccentChrome(applyBtn)
        applyBtn:SetScript("OnClick", function()
            if not ApplyFromDialog() then return end
            WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_SAVED_MSG"]) or "Position saved!") .. "|r")
            CloseNotificationCoordDialog()
        end)

        local cancelBtn = ns.UI.Factory:CreateButton(dlg)
        cancelBtn:SetSize(100, SETTINGS_COMPACT_BTN_H - 2)
        cancelBtn:SetPoint("BOTTOMRIGHT", applyBtn, "BOTTOMLEFT", -10, 0)
        local cancelBtnText = cancelBtn:GetFontString() or FontManager:CreateFontString(cancelBtn, "body", "OVERLAY")
        cancelBtnText:SetPoint("CENTER")
        cancelBtnText:SetText((ns.L and ns.L["CANCEL"]) or "Cancel")
        cancelBtn:SetFontString(cancelBtnText)
        ApplySettingsAccentChromeIdle(cancelBtn)
        WireSettingsAccentButtonHover(cancelBtn)
        RegisterSettingsAccentChrome(cancelBtn)
        cancelBtn:SetScript("OnClick", function() CloseNotificationCoordDialog() end)

        function dlg._syncFromHolder(h)
            if h ~= holder then return end
            local pt, ox, oy = ComputeAnchorOffsetsFromGhost(holder)
            dlg.selectedAnchor = pt
            xBox:SetText(tostring(ox))
            yBox:SetText(tostring(oy))
            UpdateAnchorButtonVisuals()
        end

        dlg._syncFromHolder(holder)
        dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        -- Follow profile.uiScale like every other addon dialog (unregistered in Close).
        if ns.UI_RegisterScaledFrame then ns.UI_RegisterScaledFrame(dlg) end
        dlg:Show()
    end

    -- Assigned below; declared here so this checkbox's OnClick captures the upvalue.
    local closePositionGhosts

    unifiedLayoutCheck = CreateThemedCheckbox(notifSection.content)
    unifiedLayoutCheck:SetPoint("TOPLEFT", 0, notifGridYOffset)
    local unifiedLayoutLabel = FontManager:CreateFontString(notifSection.content, "body", "OVERLAY")
    unifiedLayoutLabel:SetJustifyH("LEFT")
    unifiedLayoutLabel:SetText((ns.L and ns.L["NOTIF_UNIFIED_TOAST_LAYOUT"]) or "One position for all popup types")
    ns.UI_SetTextColorRole(unifiedLayoutLabel, "Bright")
    unifiedLayoutLabel:SetPoint("LEFT", unifiedLayoutCheck, "RIGHT", UI_SPACING.AFTER_ELEMENT, 0)
    unifiedLayoutCheck:SetChecked(WarbandNexus.db.profile.notifications.unifiedToastLayout ~= false)
    if unifiedLayoutCheck.checkTexture then unifiedLayoutCheck.checkTexture:SetShown(WarbandNexus.db.profile.notifications.unifiedToastLayout ~= false) end
    unifiedLayoutCheck:SetScript("OnClick", function(self)
        local v = self:GetChecked()
        WarbandNexus.db.profile.notifications.unifiedToastLayout = v
        if self.checkTexture then self.checkTexture:SetShown(v) end
        closePositionGhosts()
        if RefreshNotifAnchorControlsVisibility then RefreshNotifAnchorControlsVisibility() end
    end)
    notifGridYOffset = notifGridYOffset - math.max(22, ns.UI_TOGGLE_SIZE or 22) - GetHeaderToolbarGap()

    useAlertFrameCheck = CreateThemedCheckbox(notifSection.content)
    useAlertFrameCheck:SetPoint("TOPLEFT", 0, notifGridYOffset)
    local useAlertFrameLabel = FontManager:CreateFontString(notifSection.content, "body", "OVERLAY")
    useAlertFrameLabel:SetJustifyH("LEFT")
    useAlertFrameLabel:SetText((ns.L and ns.L["USE_ALERTFRAME_POSITION"]) or "Match Blizzard AlertFrame position")
    ns.UI_SetTextColorRole(useAlertFrameLabel, "Bright")
    useAlertFrameLabel:SetPoint("LEFT", useAlertFrameCheck, "RIGHT", UI_SPACING.AFTER_ELEMENT, 0)
    useAlertFrameCheck:SetChecked(WarbandNexus.db.profile.notifications.useAlertFramePosition)
    if useAlertFrameCheck.checkTexture then useAlertFrameCheck.checkTexture:SetShown(WarbandNexus.db.profile.notifications.useAlertFramePosition) end
    useAlertFrameCheck:SetScript("OnClick", function(self)
        local v = self:GetChecked()
        WarbandNexus.db.profile.notifications.useAlertFramePosition = v
        if self.checkTexture then self.checkTexture:SetShown(v) end
        if RefreshNotifAnchorControlsVisibility then RefreshNotifAnchorControlsVisibility() end
    end)
    notifGridYOffset = notifGridYOffset - math.max(22, ns.UI_TOGGLE_SIZE or 22) - GetHeaderToolbarGap()

    local btnGap = GetHeaderToolbarGap()
    local btnWidth = math.floor((notifInnerW - 2 * btnGap) / 3)
    setPosBtn = ns.UI.Factory:CreateButton(notifSection.content)
    setPosBtn:SetSize(btnWidth, SETTINGS_COMPACT_BTN_H)
    setPosBtn:SetPoint("TOPLEFT", 0, notifGridYOffset)
    local setPosBtnText = setPosBtn:GetFontString() or FontManager:CreateFontString(setPosBtn, "body", "OVERLAY")
    setPosBtnText:SetPoint("CENTER")
    setPosBtnText:SetText((ns.L and ns.L["SET_POSITION"]) or "Set Position")
    setPosBtn:SetFontString(setPosBtnText)
    ApplySettingsAccentChromeIdle(setPosBtn)
    WireSettingsAccentButtonHover(setPosBtn)
    RegisterSettingsAccentChrome(setPosBtn)
    local function saveGhostPositionBoth(ghost)
        local anchorPoint, offsetX, offsetY = ComputeAnchorOffsetsFromGhost(ghost)
        ApplyNotificationOffsetsToDb(anchorPoint, offsetX, offsetY)
    end

    function closePositionGhosts()
        CloseNotificationCoordDialog()
        WarbandNexus._notifGhostLane = nil
        if WarbandNexus._positionGhostHolder then WarbandNexus._positionGhostHolder:Hide() WarbandNexus._positionGhostHolder = nil end
        if WarbandNexus._positionGhost then WarbandNexus._positionGhost:Hide() WarbandNexus._positionGhost = nil end
        if WarbandNexus._positionGhostCriteria then WarbandNexus._positionGhostCriteria:Hide() WarbandNexus._positionGhostCriteria = nil end
        if WarbandNexus._positionGhostReminder then WarbandNexus._positionGhostReminder:Hide() WarbandNexus._positionGhostReminder = nil end
    end

    local function BeginNotificationGhostForLane(lane)
        if not lane then return end
        if NotificationPositionGhostBlocked() then return end
        local db = WarbandNexus.db.profile.notifications
        if db.unifiedToastLayout ~= false or db.useAlertFramePosition then return end
        if WarbandNexus._positionGhostHolder then
            local ap, ox, oy = ComputeAnchorOffsetsFromGhost(WarbandNexus._positionGhostHolder)
            if WarbandNexus._notifGhostLane then
                ApplyNotificationAnchorForLane(WarbandNexus._notifGhostLane, ap, ox, oy)
            else
                saveGhostPositionBoth(WarbandNexus._positionGhostHolder)
            end
            closePositionGhosts()
            WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_SAVED_MSG"]) or "Position saved!") .. "|r")
            return
        end
        local pt, px, py = "TOP", 0, -100
        if lane == "achievement" then
            pt, px, py = db.popupPoint or "TOP", db.popupX or 0, db.popupY or -100
        elseif lane == "criteria" then
            pt = db.popupPointCompact or db.popupPoint or "TOP"
            px = db.popupXCompact ~= nil and db.popupXCompact or (db.popupX or 0)
            py = db.popupYCompact ~= nil and db.popupYCompact or (db.popupY or -100)
        elseif lane == "tryCounter" then
            pt = db.tryCounterToastPoint or db.popupPoint or "TOP"
            px = db.tryCounterToastX ~= nil and db.tryCounterToastX or (db.popupX or 0)
            py = db.tryCounterToastY ~= nil and db.tryCounterToastY or (db.popupY or -100)
        elseif lane == "reminder" then
            pt = db.reminderToastPoint or "TOPRIGHT"
            px = db.reminderToastX or -42
            py = db.reminderToastY or -172
        end
        local holder = ns.UI.Factory:CreateContainer(UIParent, 400, 88, true)
        if not holder then return end
        holder:SetFrameStrata("DIALOG")
        holder:SetFrameLevel(2000)
        holder:SetMovable(true)
        holder:EnableMouse(true)
        holder:RegisterForDrag("LeftButton")
        holder:SetClampedToScreen(true)
        if ApplySettingsChrome and ns.UI_GetSemanticPositiveCard then
            local posBg, posBorder = ns.UI_GetSemanticPositiveCard(false)
            ApplySettingsChrome(holder, posBg, posBorder)
        end
        local ghostText = FontManager:CreateFontString(holder, "body", "OVERLAY")
        ghostText:SetPoint("CENTER")
        local labelKey = (lane == "achievement" and "NOTIF_GHOST_LABEL_ACHIEVEMENT")
            or (lane == "criteria" and "NOTIF_GHOST_LABEL_CRITERIA")
            or (lane == "tryCounter" and "NOTIF_GHOST_LABEL_TRY")
            or "NOTIF_GHOST_LABEL_REMINDER"
        ghostText:SetText((ns.L and ns.L[labelKey]) or lane)
        ns.UI_SetTextColorRole(ghostText, "Bright")
        holder:SetPoint(pt, UIParent, pt, px, py)
        holder:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            self:StartMoving()
        end)
        holder:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local coordDlg = WarbandNexus._notifCoordDialog
            if coordDlg and coordDlg:IsShown() and coordDlg._syncFromHolder then
                coordDlg._syncFromHolder(self)
            end
        end)
        holder:SetScript("OnMouseDown", function(_, button)
            if button == "RightButton" then
                ShowNotificationCoordDialog(holder)
            end
        end)
        holder:Show()
        WarbandNexus._notifGhostLane = lane
        WarbandNexus._positionGhostHolder = holder
        WarbandNexus:Print("|cffffcc00" .. ((ns.L and ns.L["NOTIF_DRAG_LANE_GHOST_MSG"]) or "Drag the preview, then right-click for coordinates. Click the lane button again to save.") .. "|r")
    end

    setPosBtn:SetScript("OnClick", function()
        if WarbandNexus.db.profile.notifications.useAlertFramePosition then return end
        if WarbandNexus.db.profile.notifications.unifiedToastLayout == false then
            if WarbandNexus.Print then
                WarbandNexus:Print("|cffffcc00" .. ((ns.L and ns.L["NOTIF_USE_PER_LANE_BUTTONS"]) or "Use the per-type buttons below to position each toast lane, or turn unified stack back on.") .. "|r")
            end
            return
        end
        if NotificationPositionGhostBlocked() then return end
        if WarbandNexus._positionGhostHolder then
            saveGhostPositionBoth(WarbandNexus._positionGhostHolder)
            closePositionGhosts()
            WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_SAVED_MSG"]) or "Position saved!") .. "|r")
            return
        end
        WarbandNexus._notifGhostLane = nil
        local db = WarbandNexus.db.profile.notifications
        local pt = db.popupPoint or "TOP"
        local px, py = db.popupX or 0, db.popupY or -100

        local holderH = 88 + 10 + 88
        local holder = ns.UI.Factory:CreateContainer(UIParent, 400, holderH, true)
        if not holder then return end
        holder:SetFrameStrata("DIALOG")
        holder:SetFrameLevel(2000)
        holder:SetMovable(true)
        holder:EnableMouse(true)
        holder:RegisterForDrag("LeftButton")
        holder:SetClampedToScreen(true)
        if ApplySettingsChrome then
            local shellBg = SettingsDialogShellBg()
            ApplySettingsChrome(holder, shellBg, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.85 })
        end

        local topPane = ns.UI.Factory:CreateContainer(holder, 400, 88, true)
        if topPane then
            topPane:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
            if ApplySettingsChrome and ns.UI_GetSemanticPositiveCard then
                local posBg, posBorder = ns.UI_GetSemanticPositiveCard(false)
                ApplySettingsChrome(topPane, posBg, posBorder)
            end
            local ghostText = FontManager:CreateFontString(topPane, "body", "OVERLAY")
            ghostText:SetPoint("CENTER")
            ghostText:SetText((ns.L and ns.L["NOTIFICATION_GHOST_MAIN"]) or "Achievement / notification")
            ns.UI_SetTextColorRole(ghostText, "Bright")
        end
        local botPane = ns.UI.Factory:CreateContainer(holder, 400, 88, true)
        if botPane then
            botPane:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(88 + 10))
            if ApplySettingsChrome then
                local listenBg = ns.UI_GetAccentListeningBackdrop and ns.UI_GetAccentListeningBackdrop() or SettingsControlChromeHover()
                ApplySettingsChrome(botPane, listenBg, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.85 })
            end
            local ghostCriteriaText = FontManager:CreateFontString(botPane, "body", "OVERLAY")
            ghostCriteriaText:SetPoint("CENTER")
            ghostCriteriaText:SetText((ns.L and ns.L["NOTIFICATION_GHOST_CRITERIA"]) or "Criteria / To-Do lane")
            ns.UI_SetTextColorRole(ghostCriteriaText, "Bright")
        end

        holder:SetPoint(pt, UIParent, pt, px, py)
        holder:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            self:StartMoving()
        end)
        holder:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local coordDlg = WarbandNexus._notifCoordDialog
            if coordDlg and coordDlg:IsShown() and coordDlg._syncFromHolder then
                coordDlg._syncFromHolder(self)
            end
        end)
        holder:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                WarbandNexus._notifGhostLane = nil
                ShowNotificationCoordDialog(self)
            end
        end)
        holder:Show()
        WarbandNexus._positionGhostHolder = holder

        WarbandNexus:Print("|cffffcc00" .. ((ns.L and ns.L["DRAG_POSITION_STACK_MSG"]) or "Drag the stacked preview. Right-click for coordinates. Click Set Position again to save.") .. "|r")
    end)

    local resetBtn = ns.UI.Factory:CreateButton(notifSection.content)
    resetBtn:SetSize(btnWidth, SETTINGS_COMPACT_BTN_H)
    resetBtn:SetPoint("LEFT", setPosBtn, "RIGHT", btnGap, 0)
    local resetBtnText = resetBtn:GetFontString() or FontManager:CreateFontString(resetBtn, "body", "OVERLAY")
    resetBtnText:SetPoint("CENTER")
    resetBtnText:SetText((ns.L and ns.L["RESET_POSITION"]) or "Reset Position")
    resetBtn:SetFontString(resetBtnText)
    ApplySettingsAccentChromeIdle(resetBtn)
    WireSettingsAccentButtonHover(resetBtn)
    RegisterSettingsAccentChrome(resetBtn)
    resetBtn:SetScript("OnClick", function()
        if WarbandNexus.db.profile.notifications.useAlertFramePosition then return end
        local db = WarbandNexus.db.profile.notifications
        db.popupPoint = "TOP"
        db.popupX = 0
        db.popupY = -100
        db.popupPointCompact = "TOP"
        db.popupXCompact = 0
        db.popupYCompact = -100
        db.tryCounterToastPoint = "TOP"
        db.tryCounterToastX = 0
        db.tryCounterToastY = -100
        db.useAlertFramePosition = false
        db.unifiedToastLayout = true
        SyncLegacyReminderToastFromProgressLane(db)
        if useAlertFrameCheck then useAlertFrameCheck:SetChecked(false); if useAlertFrameCheck.checkTexture then useAlertFrameCheck.checkTexture:SetShown(false) end end
        if unifiedLayoutCheck then unifiedLayoutCheck:SetChecked(true); if unifiedLayoutCheck.checkTexture then unifiedLayoutCheck.checkTexture:SetShown(true) end end
        if RefreshNotifAnchorControlsVisibility then RefreshNotifAnchorControlsVisibility() end
        WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_RESET_MSG"]) or "Position reset to default.") .. "|r")
    end)

    local testBtn = ns.UI.Factory:CreateButton(notifSection.content)
    testBtn:SetSize(btnWidth, SETTINGS_COMPACT_BTN_H)
    testBtn:SetPoint("LEFT", resetBtn, "RIGHT", btnGap, 0)
    local testBtnText = testBtn:GetFontString() or FontManager:CreateFontString(testBtn, "body", "OVERLAY")
    testBtnText:SetPoint("CENTER")
    testBtnText:SetText((ns.L and ns.L["TEST_NOTIFICATION"]) or "Test Notification")
    testBtn:SetFontString(testBtnText)
    ApplySettingsAccentChromeIdle(testBtn)
    WireSettingsAccentButtonHover(testBtn)
    RegisterSettingsAccentChrome(testBtn)
    testBtn:SetScript("OnClick", function()
        if WarbandNexus.TestNotificationStack then
            WarbandNexus:TestNotificationStack()
        elseif WarbandNexus.Notify then
            WarbandNexus:Notify("achievement", (ns.L and ns.L["TEST_NOTIFICATION_TITLE"]) or "Test Notification", nil, { action = (ns.L and ns.L["TEST_NOTIFICATION_MSG"]) or "Position test" })
        end
    end)
    notifGridYOffset = notifGridYOffset - SETTINGS_COMPACT_BTN_H - GetHeaderToolbarGap()

    notifPerLaneLabel = FontManager:CreateFontString(notifSection.content, "small", "OVERLAY")
    notifPerLaneLabel:SetPoint("TOPLEFT", 0, notifGridYOffset)
    notifPerLaneLabel:SetWidth(notifInnerW)
    notifPerLaneLabel:SetJustifyH("LEFT")
    notifPerLaneLabel:SetWordWrap(true)
    notifPerLaneLabel:SetNonSpaceWrap(false)
    notifPerLaneLabel:SetText((ns.L and ns.L["NOTIF_PER_LANE_HINT"]) or "Separate position per popup type: click a lane, drag the preview, right-click for X/Y.")
    ns.UI_SetTextColorRole(notifPerLaneLabel, "Normal")
    notifGridYOffset = notifGridYOffset - math.max(SETTINGS_ANCHOR_DESC_MIN_HEIGHT, notifPerLaneLabel:GetStringHeight()) - GetHeaderToolbarGap()

    local laneBtnW = math.floor((notifInnerW - 3 * btnGap) / 4)
    local laneDefs = {
        { id = "achievement", loc = "NOTIF_POS_BTN_ACH", fallback = "Achievement" },
        { id = "criteria", loc = "NOTIF_POS_BTN_CRITERIA", fallback = "Criteria" },
        { id = "tryCounter", loc = "NOTIF_POS_BTN_TRY", fallback = "Try count" },
        { id = "reminder", loc = "NOTIF_POS_BTN_REMINDER", fallback = "Reminder" },
    }
    for li = 1, #laneDefs do
        local ld = laneDefs[li]
        local lb = ns.UI.Factory:CreateButton(notifSection.content)
        lb:SetSize(laneBtnW, SETTINGS_COMPACT_BTN_H)
        lb:SetPoint("TOPLEFT", (li - 1) * (laneBtnW + btnGap), notifGridYOffset)
        local lt = lb:GetFontString() or FontManager:CreateFontString(lb, "small", "OVERLAY")
        lt:SetPoint("CENTER", 0, 0)
        lt:SetText((ns.L and ns.L[ld.loc]) or ld.fallback)
        ns.UI_SetTextColorRole(lt, "Bright")
        lb:SetFontString(lt)
        ApplySettingsAccentChromeIdle(lb)
        WireSettingsAccentButtonHover(lb)
        RegisterSettingsAccentChrome(lb)
        local laneId = ld.id
        lb:SetScript("OnClick", function()
            BeginNotificationGhostForLane(laneId)
        end)
        lanePosButtons[#lanePosButtons + 1] = lb
    end
    notifGridYOffset = notifGridYOffset - SETTINGS_COMPACT_BTN_H - GetHeaderToolbarGap()

    RefreshNotifAnchorControlsVisibility = function()
        local db = WarbandNexus.db.profile.notifications
        if not db then return end
        local unified = db.unifiedToastLayout ~= false
        local blizz = db.useAlertFramePosition
        if setPosBtn then
            setPosBtn:SetShown(unified)
            if unified then
                if blizz then setPosBtn:Disable(); setPosBtn:SetAlpha(0.5)
                else setPosBtn:Enable(); setPosBtn:SetAlpha(1) end
            end
        end
        if resetBtn then
            resetBtn:SetShown(unified)
            if unified then
                if blizz then resetBtn:Disable(); resetBtn:SetAlpha(0.5)
                else resetBtn:Enable(); resetBtn:SetAlpha(1) end
            end
        end
        for i = 1, #lanePosButtons do
            local b = lanePosButtons[i]
            if b then
                b:SetShown(not unified)
                if not unified then
                    if blizz then b:Disable(); b:SetAlpha(0.35)
                    else b:Enable(); b:SetAlpha(1) end
                end
            end
        end
        if notifPerLaneLabel then
            notifPerLaneLabel:SetShown(not unified)
        end
    end

    if WarbandNexus.db.profile.notifications.useAlertFramePosition then
        setPosBtn:Disable() setPosBtn:SetAlpha(0.5) resetBtn:Disable() resetBtn:SetAlpha(0.5)
    else
        setPosBtn:Enable() setPosBtn:SetAlpha(1) resetBtn:Enable() resetBtn:SetAlpha(1)
    end
    RefreshNotifAnchorControlsVisibility()

    if durationLabel then
        table.insert(notifExternalDependents, { type = "label", widget = durationLabel })
    end
    if durationSlider then
        table.insert(notifExternalDependents, { type = "slider", widget = durationSlider, label = durationLabel })
    end
    table.insert(notifExternalDependents, { type = "button", widget = setPosBtn })
    table.insert(notifExternalDependents, { type = "button", widget = resetBtn })
    table.insert(notifExternalDependents, { type = "button", widget = testBtn })
    for i = 1, #lanePosButtons do
        table.insert(notifExternalDependents, { type = "button", widget = lanePosButtons[i] })
    end
    table.insert(notifExternalDependents, { type = "label", widget = notifPerLaneLabel, role = "Muted" })
    table.insert(notifExternalDependents, { type = "button", widget = unifiedLayoutCheck })
    table.insert(notifExternalDependents, { type = "label", widget = unifiedLayoutLabel, role = "Bright" })
    table.insert(notifExternalDependents, { type = "label", widget = useAlertFrameLabel, role = "Bright" })
    table.insert(notifExternalDependents, { type = "button", widget = useAlertFrameCheck })
    
    -- Apply initial disabled state if notifications are OFF
    local notifInitialEnabled = WarbandNexus.db.profile.notifications.enabled
    if not notifInitialEnabled then
        for di = 1, #notifExternalDependents do
            local dep = notifExternalDependents[di]
            if dep.type == "slider" then
                dep.widget:Disable()
                dep.widget:SetAlpha(0.35)
                if dep.label then ns.UI_SetTextColorRole(dep.label, "Dim", 0.6) end
            elseif dep.type == "button" then
                dep.widget:Disable()
                dep.widget:SetAlpha(0.35)
            elseif dep.type == "label" then
                ns.UI_SetTextColorRole(dep.widget, "Dim", 0.6)
            end
        end
    end
    
    -- Calculate section height
    local contentHeight = SettingsMeasuredSectionContentHeight(notifGridYOffset)
    FinalizeSettingsSectionHeight(notifSection, contentHeight, false)
    
    -- Move to next section
    yOffset = yOffset - notifSection:GetHeight() - SETTINGS_SECTION_GAP
    return yOffset
end
