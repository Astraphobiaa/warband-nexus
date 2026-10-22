--[[
    Warband Nexus - Settings UI general panel (display, item tooltips, keybinding, window scale).
    Split from SettingsUI.lua (BuildSettings panel body; file size / Lua 5.1 limits).
    Loaded after Modules/UI/SettingsUI.lua: helpers come from ns.SettingsUI._H at call time.
]]

local ADDON_NAME, ns = ...
local M = ns.SettingsUI
assert(M and M._H, "SettingsUI_General.lua loaded before SettingsUI.lua - check the TOC")

-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local E = ns.Constants.EVENTS

-- Keybind capture state (moved from SettingsUI.lua; only this panel reads/writes it).
local settingsKeybindStopListening = nil
local settingsKeybindIsListening = false
local settingsKeybindButton = nil
local settingsKeybindCaptureFrame = nil

---@param ctx table `{ parent, effectiveWidth, sideInset, yOffset, skipPanelIntro, AnchorSectionTop }`
---@return number yOffset
function M.AppendGeneralPanel(ctx)
    local H = M._H
    local WarbandNexus = H.WarbandNexus
    local COLORS = H.COLORS
    local FontManager = H.FontManager
    local ns = H.ns
    local SettingsKeybind = H.SettingsKeybind
    local SETTINGS_SECTION_GAP = H.SETTINGS_SECTION_GAP
    local SETTINGS_BTN_H = H.SETTINGS_BTN_H
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
    local CreateButtonGrid = H.CreateButtonGrid
    local FinalizeSettingsSectionHeight = H.FinalizeSettingsSectionHeight
    local SettingsMeasuredSectionContentHeight = H.SettingsMeasuredSectionContentHeight
    local ApplySettingsChrome = H.ApplySettingsChrome
    local ApplySettingsAccentChromeIdle = H.ApplySettingsAccentChromeIdle
    local WireSettingsAccentButtonHover = H.WireSettingsAccentButtonHover
    local RegisterSettingsAccentChrome = H.RegisterSettingsAccentChrome
    local SettingsControlChromeHover = H.SettingsControlChromeHover
    local Settings_ShowWrappedTooltip = H.Settings_ShowWrappedTooltip
    local sliderElements = H.sliderElements
    local parent = ctx.parent
    local effectiveWidth = ctx.effectiveWidth
    local sideInset = ctx.sideInset
    local yOffset = ctx.yOffset
    local skipPanelIntro = ctx.skipPanelIntro
    local AnchorSectionTop = ctx.AnchorSectionTop

    -- GENERAL SETTINGS
    yOffset = AppendSettingsPanelIntro(parent, "general", effectiveWidth, yOffset, sideInset, skipPanelIntro)
    local generalSection = CreateSection(parent, nil, effectiveWidth)
    AnchorSectionTop(generalSection, yOffset)
    
    -- General "Startup" options (login stats). Minimap + Easy Access shortcuts now live
    -- together in the "Shortcuts" (access) panel; item tooltips are a separate subsection below.
    local generalFeatureOptions = {
        {
            key = "requestPlayedTimeOnLogin",
            label = (ns.L and ns.L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN"]) or "Request played time on login",
            tooltip = (ns.L and ns.L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN_DESC"]) or "When enabled, the addon requests /played data in the background to update statistics. Chat output from that request is suppressed. When disabled, no automatic request on login.",
            get = function() return WarbandNexus.db.profile.requestPlayedTimeOnLogin ~= false end,
            set = function(value) WarbandNexus.db.profile.requestPlayedTimeOnLogin = value end,
        },
    }

    local tooltipOptions = {
        {
            key = "showTooltipItemCount",
            label = (ns.L and ns.L["CONFIG_SHOW_ITEMS_TOOLTIP"]) or "Show Items in Tooltips",
            tooltip = (ns.L and ns.L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"]) or "Display Warband and Character item counts in item tooltips.",
            get = function() return WarbandNexus.db.profile.showTooltipItemCount ~= false end,
            set = function(value)
                WarbandNexus.db.profile.showTooltipItemCount = value
                WarbandNexus.db.profile.showItemCount = value
            end,
        },
        {
            key = "showTooltipItemID",
            label = (ns.L and ns.L["CONFIG_SHOW_TOOLTIP_ITEM_ID"]) or "Show Item ID in Tooltips",
            tooltip = (ns.L and ns.L["CONFIG_SHOW_TOOLTIP_ITEM_ID_DESC"]) or "Append the numeric item ID at the bottom of item tooltips.",
            get = function() return WarbandNexus.db.profile.showTooltipItemID ~= false end,
            set = function(value) WarbandNexus.db.profile.showTooltipItemID = value end,
        },
        {
            key = "showSectionGoldTotal",
            label = (ns.L and ns.L["CONFIG_SECTION_GOLD_TOTAL"]) or "Section Gold Total",
            tooltip = (ns.L and ns.L["CONFIG_SECTION_GOLD_TOTAL_DESC"]) or "Show the summed gold of each section on its header in the Characters tab. Uses the last amount recorded for each character, so a character you have not played since installing adds nothing.",
            get = function() return WarbandNexus.db.profile.showSectionGoldTotal ~= false end,
            set = function(value)
                WarbandNexus.db.profile.showSectionGoldTotal = value
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "chars", skipCooldown = true })
            end,
        },
        {
            key = "showCharacterRealmName",
            label = (ns.L and ns.L["CONFIG_SHOW_CHARACTER_REALM"]) or "Show Realm Name",
            tooltip = (ns.L and ns.L["CONFIG_SHOW_CHARACTER_REALM_DESC"]) or "Show the realm name under each character name in the Characters tab. Turn off for a cleaner list.",
            get = function() return WarbandNexus.db.profile.showCharacterRealmName ~= false end,
            set = function(value)
                WarbandNexus.db.profile.showCharacterRealmName = value
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "chars", skipCooldown = true })
            end,
        },
    }

    local generalContentW = GetSettingsSectionContentWidth(effectiveWidth)
    local generalStackY = 0
    generalStackY = StackSettingsSubPanel(generalSection.content, generalContentW, 0, function(inner, iw)
        local hdrGap = GetHeaderToolbarGap()
        local cy = 0
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_GENERAL_INTERFACE"]) or "Interface",
            iw, cy, { skipGapBefore = true })

        -- Language selector. All locales load into ns.LOCALES regardless of the game client,
        -- so any language is selectable; "auto" follows the game client locale (the default).
        -- Untranslated keys and Blizzard game terms fall back to English (see Core.lua).
        cy = CreateDropdownWidget(inner, {
            name = (ns.L and ns.L["LANGUAGE_SELECT_LABEL"]) or "Language",
            desc = (ns.L and ns.L["LANGUAGE_SELECT_DESC"]) or "Choose the addon interface language.",
            stackBelowLabel = true,
            -- Endonyms (native names, raw UTF-8) so each language is recognizable in any UI language.
            valueOrder = { "auto", "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "trTR", "zhCN", "zhTW" },
            values = {
                auto = (ns.L and ns.L["LANGUAGE_AUTO"]) or "Auto (Game Client)",
                enUS = "English",
                deDE = "Deutsch",
                esES = "Español (EU)",
                esMX = "Español (MX)",
                frFR = "Français",
                itIT = "Italiano",
                -- Korean/Chinese endonyms need CJK/Hangul glyphs the bundled Latin fonts lack
                -- (they render as boxes under Noto Sans), so use Latin labels that render anywhere.
                koKR = "Korean",
                ptBR = "Português (BR)",
                ruRU = "Русский",
                trTR = "Türkçe",
                zhCN = "Chinese (Simplified)",
                zhTW = "Chinese (Traditional)",
            },
            get = function()
                return WarbandNexus.db.profile.languageOverride or "auto"
            end,
            set = function(_, value)
                local p = WarbandNexus.db.profile
                if (p.languageOverride or "auto") == value then return end
                p.languageOverride = value
                -- Locale is merged at OnInitialize and baked into already-built frames;
                -- a reload rebuilds the whole UI cleanly in the new language.
                if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
            end,
        }, cy)

        -- Turkish-only note. The bundled Noto Sans covers Turkish, but a user who kept a custom
        -- font (ApplyLocaleFont respects an explicit non-default choice) can still hit missing
        -- glyphs, so point them at fonts that render the full set. Shown for an explicit trTR
        -- selection only, matching when the locale font swap applies.
        if (WarbandNexus.db.profile.languageOverride or "auto") == "trTR" then
            local trFontHint = FontManager:CreateFontString(inner, "body", "OVERLAY")
            trFontHint:SetPoint("TOPLEFT", 0, cy)
            trFontHint:SetWidth(iw)
            trFontHint:SetJustifyH("LEFT")
            trFontHint:SetWordWrap(true)
            trFontHint:SetText((ns.L and ns.L["LANGUAGE_TR_FONT_HINT"])
                or "If Turkish characters do not display correctly, try a different font such as Exo or Arial.")
            ns.UI_SetTextColorRole(trFontHint, "Muted")
            cy = cy - math.max(18, trFontHint:GetStringHeight()) - GetHeaderToolbarGap()
        end

        -- Keybinding row (fixed label column + controls)
        local labelColW = math.min(170, math.floor(iw * 0.34))
        local keybindTitle = (ns.L and ns.L["KEYBINDING"]) or "Keybinding"
        local keybindLabel = FontManager:CreateFontString(inner, "body", "OVERLAY")
        keybindLabel:SetPoint("TOPLEFT", 0, cy)
        keybindLabel:SetWidth(labelColW)
        keybindLabel:SetJustifyH("LEFT")
        keybindLabel:SetWordWrap(false)
        keybindLabel:SetText(keybindTitle .. ":")
        ns.UI_SetTextColorRole(keybindLabel, "Bright")

        local keybindBtn = ns.UI.Factory:CreateButton(inner, 168, SETTINGS_BTN_H, false)
        settingsKeybindButton = keybindBtn
        -- Top-anchor the button at the row baseline (cy) so it doesn't ride ~19px above the row
        -- (it was LEFT->label RIGHT, centering the tall button on the short label). Then vertically
        -- centre the label text on the button so label + box + X sit on one symmetric line.
        keybindBtn:SetPoint("TOPLEFT", inner, "TOPLEFT", labelColW + hdrGap, cy)
        keybindLabel:ClearAllPoints()
        keybindLabel:SetPoint("LEFT", inner, "LEFT", 0, 0)
        keybindLabel:SetPoint("RIGHT", keybindBtn, "LEFT", -hdrGap, 0)
        keybindLabel:SetPoint("TOP", keybindBtn, "TOP", 0, 0)
        keybindLabel:SetPoint("BOTTOM", keybindBtn, "BOTTOM", 0, 0)
        keybindLabel:SetJustifyV("MIDDLE")
    if ApplySettingsChrome then
        ApplySettingsAccentChromeIdle(keybindBtn)
    end
    WireSettingsAccentButtonHover(keybindBtn)
    RegisterSettingsAccentChrome(keybindBtn)

    local keybindBtnText = FontManager:CreateFontString(keybindBtn, "body", "OVERLAY")
    -- Bound to the button on both sides: a CENTER-only anchor let long combos ("ALT-CTRL-SHIFT-...")
    -- spill past the button edges, where the opaque clear button and the label painted over them.
    local keybindTextPad = UI_SPACING.AFTER_ELEMENT
    keybindBtnText:SetPoint("LEFT", keybindBtn, "LEFT", keybindTextPad, 0)
    keybindBtnText:SetPoint("RIGHT", keybindBtn, "RIGHT", -keybindTextPad, 0)
    keybindBtnText:SetJustifyH("CENTER")
    keybindBtnText:SetWordWrap(false)
    keybindBtnText:SetText(SettingsKeybind.GetToggleBindingDisplayText())
    ns.UI_SetTextColorRole(keybindBtnText, "Bright")

    local isListening = false
    local captureFrame = settingsKeybindCaptureFrame
    if not captureFrame then
        captureFrame = ns.UI.Factory and ns.UI.Factory.CreateContainer and ns.UI.Factory:CreateContainer(UIParent, 1, 1, false)
        if not captureFrame then
            captureFrame = CreateFrame("Frame", nil, UIParent)
        end
        captureFrame:SetAllPoints(UIParent)
        captureFrame:Hide()
        settingsKeybindCaptureFrame = captureFrame
    end

    local function StopListening()
        isListening = false
        settingsKeybindIsListening = false
        if captureFrame then
            if captureFrame.EnableKeyboard then
                captureFrame:EnableKeyboard(false)
            end
            if captureFrame.SetPropagateKeyboardInput then
                captureFrame:SetPropagateKeyboardInput(true)
            end
            captureFrame:Hide()
        end
        keybindBtnText:SetText(SettingsKeybind.GetToggleBindingDisplayText())
        ns.UI_SetTextColorRole(keybindBtnText, "Bright")
        ApplySettingsAccentChromeIdle(keybindBtn)
    end

    local function StartListening()
        if InCombatLockdown() then return end
        isListening = true
        settingsKeybindIsListening = true
        if captureFrame then
            captureFrame:Show()
            if captureFrame.EnableKeyboard then
                captureFrame:EnableKeyboard(true)
            end
            if captureFrame.SetPropagateKeyboardInput then
                captureFrame:SetPropagateKeyboardInput(false)
            end
        end
        keybindBtnText:SetText((ns.L and ns.L["KEYBINDING_PRESS_KEY"]) or "Press a key...")
        keybindBtnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        if ApplySettingsChrome then
            local listenBg = ns.UI_GetAccentListeningBackdrop and ns.UI_GetAccentListeningBackdrop() or SettingsControlChromeHover()
            ApplySettingsChrome(keybindBtn, listenBg, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1 })
        end
    end
    settingsKeybindStopListening = StopListening
    SettingsKeybind.RegisterCaptureHooks(StopListening, keybindBtn)
    StopListening()

    keybindBtn:SetScript("OnClick", function()
        if isListening then
            StopListening()
        else
            StartListening()
        end
    end)

    captureFrame:SetScript("OnKeyDown", function(_, key)
        if not isListening then return end
        if SettingsKeybind.IGNORED_KEYS[key] then return end

        if key == "ESCAPE" then
            StopListening()
            return
        end

        if InCombatLockdown() then
            if WarbandNexus and WarbandNexus.Print then
                WarbandNexus:Print("|cffff6600" .. ((ns.L and ns.L["KEYBINDING_COMBAT"]) or "Cannot change keybindings in combat.") .. "|r")
            end
            StopListening()
            return
        end

        local prefix = ""
        if IsShiftKeyDown() then prefix = "SHIFT-" end
        if IsControlKeyDown() then prefix = "CTRL-" .. prefix end
        if IsAltKeyDown() then prefix = "ALT-" .. prefix end

        local fullKey = prefix .. key
        if SettingsKeybind.IsForbiddenToggleKeybind(fullKey) then
            SettingsKeybind.SaveToggleKeybind(fullKey) -- existing path prints warning + clears
            StopListening()
            return
        end
        if not WarbandNexus or not WarbandNexus.db then
            StopListening()
            return
        end
        WarbandNexus.db.profile.toggleKeybind = fullKey
        -- Defer binding install until the physical key is released; otherwise the OS-level
        -- key-repeat / OnKeyUp of the same press can fire the freshly-bound toggle and close
        -- Settings immediately after "Keybinding saved".
        ns._wnSuppressToggleMainOnce = true
        local settleFrame = captureFrame
        local function InstallBindingNow()
            if not ns._wnSuppressToggleMainOnce then return end
            if WarbandNexus and WarbandNexus.ApplyToggleKeybind then
                WarbandNexus:ApplyToggleKeybind()
            end
            -- Clear suppression one more frame later so any queued toggle is swallowed.
            C_Timer.After(0, function()
                ns._wnSuppressToggleMainOnce = nil
            end)
        end
        if settleFrame then
            settleFrame:SetScript("OnKeyUp", function(self)
                self:SetScript("OnKeyUp", nil)
                InstallBindingNow()
            end)
        end
        -- Fallback: if OnKeyUp never arrives (modifier-only release, focus change),
        -- install after a short delay.
        C_Timer.After(0.35, function()
            if settleFrame and settleFrame.SetScript then
                settleFrame:SetScript("OnKeyUp", nil)
            end
            InstallBindingNow()
        end)

        if WarbandNexus and WarbandNexus.Print then
            WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["KEYBINDING_SAVED"]) or "Keybinding saved.") .. "|r")
        end

        StopListening()
    end)

    keybindBtn:SetScript("OnEnter", function(self)
        local t = (ns.L and ns.L["KEYBINDING_TOOLTIP"]) or "Click to set a keybinding for toggling Warband Nexus.\nPress ESC to cancel."
        -- The button label is width-bounded, so long combos read in full here.
        local bound = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
            and WarbandNexus.db.profile.toggleKeybind
        if bound and bound ~= "" then
            t = t .. "\n" .. SettingsKeybind.GetToggleBindingDisplayText()
        end
        Settings_ShowWrappedTooltip(self, t)
    end)
    keybindBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Clear binding button
        local clearBtn = ns.UI.Factory:CreateButton(inner, SETTINGS_BTN_H, SETTINGS_BTN_H, false)
        clearBtn:SetPoint("LEFT", keybindBtn, "RIGHT", hdrGap, 0)
        if ApplySettingsChrome and ns.UI_GetSemanticNegativeCard then
            local negBg, negBorder = ns.UI_GetSemanticNegativeCard(false)
            ApplySettingsChrome(clearBtn, negBg, negBorder)
        end

        local clearIcon = clearBtn:CreateTexture(nil, "ARTWORK")
    clearIcon:SetSize(12, 12)
    clearIcon:SetPoint("CENTER")
    ns.UI_SetIcon(clearIcon, "close")
    clearIcon:SetVertexColor(0.9, 0.3, 0.3)

    clearBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        SettingsKeybind.SaveToggleKeybind(nil)
        StopListening()
    end)
    clearBtn:SetScript("OnEnter", function(self)
        clearIcon:SetVertexColor(1, 0.2, 0.2)
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["KEYBINDING_CLEAR"]) or "Clear keybinding")
    end)
        clearBtn:SetScript("OnLeave", function()
            clearIcon:SetVertexColor(0.9, 0.3, 0.3)
            GameTooltip:Hide()
        end)

        cy = cy - SETTINGS_BTN_H - hdrGap

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_GENERAL_CONTROLS"]) or "Controls & Scaling",
            iw, cy, {})

        cy = CreateSliderWidget(inner, {
            name = (ns.L and ns.L["SCROLL_SPEED"]) or "Scroll Speed",
            desc = (ns.L and ns.L["SCROLL_SPEED_TOOLTIP"]) or "Multiplier for scroll speed (1.0x = 28 px per step)",
            min = 0.5,
            max = 2.0,
            step = 0.1,
            get = function() return WarbandNexus.db.profile.scrollSpeed or 1.0 end,
            set = function(_, value)
                WarbandNexus.db.profile.scrollSpeed = math.floor(value * 10 + 0.5) / 10
            end,
            valueFormat = function(v) return string.format("%.1fx", v) end,
        }, cy, sliderElements)

        local uiScaleSlider
        cy, uiScaleSlider = CreateSliderWidget(inner, {
            name = (ns.L and ns.L["UI_SCALE"]) or "UI Scale",
            desc = (ns.L and ns.L["UI_SCALE_TOOLTIP"]) or "Scale the entire addon window. Reduce if the window takes up too much screen space.",
            min = 0.6,
            max = 1.5,
            step = 0.05,
            applyOnRelease = true,
            get = function() return WarbandNexus.db.profile.uiScale or 1.0 end,
            set = function(_, value)
                value = math.floor(value * 20 + 0.5) / 20
                WarbandNexus.db.profile.uiScale = value
                if WarbandNexus.ApplyUIScale then
                    WarbandNexus:ApplyUIScale(value)
                end
            end,
            valueFormat = function(v) return string.format("%d%%", v * 100) end,
        }, cy, sliderElements)

        cy = CreateButtonGrid(inner, {
            {
                label = (ns.L and ns.L["SETTINGS_AUTO_FIT_UI_SCALE"]) or "Auto-Fit Scale",
                text = (ns.L and ns.L["SETTINGS_AUTO_FIT_UI_SCALE"]) or "Auto-Fit Scale",
                tooltip = (ns.L and ns.L["SETTINGS_AUTO_FIT_UI_SCALE_DESC"])
                    or "Automatically detect display resolution and apply the recommended UI scale for this screen.",
                func = function()
                    local rec = WarbandNexus.API_GetRecommendedUIScale and WarbandNexus:API_GetRecommendedUIScale() or 1.0
                    WarbandNexus.db.profile.uiScale = rec
                    if WarbandNexus.ApplyUIScale then
                        WarbandNexus:ApplyUIScale(rec)
                    end
                    if uiScaleSlider then
                        if uiScaleSlider.SetValue then uiScaleSlider:SetValue(rec) end
                        if uiScaleSlider.UpdateLabel then uiScaleSlider.UpdateLabel(rec) end
                    end
                end,
                onClick = function()
                    local rec = WarbandNexus.API_GetRecommendedUIScale and WarbandNexus:API_GetRecommendedUIScale() or 1.0
                    WarbandNexus.db.profile.uiScale = rec
                    if WarbandNexus.ApplyUIScale then
                        WarbandNexus:ApplyUIScale(rec)
                    end
                    if uiScaleSlider then
                        if uiScaleSlider.SetValue then uiScaleSlider:SetValue(rec) end
                        if uiScaleSlider.UpdateLabel then uiScaleSlider.UpdateLabel(rec) end
                    end
                end,
            },
            {
                label = (ns.L and ns.L["RESET_DEFAULT"]) or "Reset (100%)",
                text = (ns.L and ns.L["RESET_DEFAULT"]) or "Reset (100%)",
                tooltip = (ns.L and ns.L["RESET_TO_DEFAULT_TOOLTIP"]) or "Reset UI Scale to 100%.",
                func = function()
                    WarbandNexus.db.profile.uiScale = 1.0
                    if WarbandNexus.ApplyUIScale then
                        WarbandNexus:ApplyUIScale(1.0)
                    end
                    if uiScaleSlider then
                        if uiScaleSlider.SetValue then uiScaleSlider:SetValue(1.0) end
                        if uiScaleSlider.UpdateLabel then uiScaleSlider.UpdateLabel(1.0) end
                    end
                end,
                onClick = function()
                    WarbandNexus.db.profile.uiScale = 1.0
                    if WarbandNexus.ApplyUIScale then
                        WarbandNexus:ApplyUIScale(1.0)
                    end
                    if uiScaleSlider then
                        if uiScaleSlider.SetValue then uiScaleSlider:SetValue(1.0) end
                        if uiScaleSlider.UpdateLabel then uiScaleSlider.UpdateLabel(1.0) end
                    end
                end,
            },
        }, cy, iw, 150)

        cy = select(1, CreateCheckboxGrid(inner, {
            {
                key = "mainWindowDense",
                label = (ns.L and ns.L["SETTINGS_COMPACT_MAIN_WINDOW_LABEL"]) or "Compact main-window footprint",
                tooltip = (ns.L and ns.L["SETTINGS_COMPACT_MAIN_WINDOW_HINT"])
                    or "Tighter resize minimums and modest default sizing. Horizontal scroll still covers wide tabs.",
                get = function()
                    local p = WarbandNexus.db.profile
                    return (p.mainWindowDensity or "standard") == "compact"
                end,
                set = function(on)
                    WarbandNexus.db.profile.mainWindowDensity = on and "compact" or "standard"
                    if WarbandNexus.UI_ClampMainFrameResizeBoundsFromProfile then
                        WarbandNexus:UI_ClampMainFrameResizeBoundsFromProfile()
                    end
                    if WarbandNexus.RefreshUI then
                        WarbandNexus:RefreshUI()
                    end
                end,
            },
        }, cy, iw, { maxColumns = 1 }))

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_GENERAL_TOOLTIPS"]) or "Item tooltips",
            iw, cy, {})
        cy = CreateCheckboxGrid(inner, tooltipOptions, cy, iw)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_GENERAL_STARTUP"]) or "Startup",
            iw, cy, {})
        cy = CreateCheckboxGrid(inner, generalFeatureOptions, cy, iw)

        return cy
    end, { flat = true, noTrailingGap = true })

    local generalContentHeight = SettingsMeasuredSectionContentHeight(generalStackY)
    FinalizeSettingsSectionHeight(generalSection, generalContentHeight, false)
    
    -- Move to next section
    yOffset = yOffset - generalSection:GetHeight() - SETTINGS_SECTION_GAP
    return yOffset
end
