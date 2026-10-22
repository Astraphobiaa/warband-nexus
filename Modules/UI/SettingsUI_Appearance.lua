--[[
    Warband Nexus - Settings UI appearance panel (theme, fonts, scaling).
    Split from SettingsUI.lua (BuildSettings panel body; file size / Lua 5.1 limits).
    Loaded after Modules/UI/SettingsUI.lua: helpers come from ns.SettingsUI._H at call time.
]]

local ADDON_NAME, ns = ...
local M = ns.SettingsUI
assert(M and M._H, "SettingsUI_Appearance.lua loaded before SettingsUI.lua - check the TOC")

-- Legacy floating settings frame (moved from SettingsUI.lua; only this panel reads/writes it).
local settingsFrame = nil

---@param ctx table `{ parent, effectiveWidth, sideInset, yOffset, skipPanelIntro, AnchorSectionTop }`
---@return number yOffset
function M.AppendAppearancePanel(ctx)
    local H = M._H
    local WarbandNexus = H.WarbandNexus
    local COLORS = H.COLORS
    local FontManager = H.FontManager
    local ns = H.ns
    local SETTINGS_SECTION_GAP = H.SETTINGS_SECTION_GAP
    local SETTINGS_BTN_H = H.SETTINGS_BTN_H
    local SETTINGS_CHECKBOX_GRID_INDENT = H.SETTINGS_CHECKBOX_GRID_INDENT
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
    local CreateSettingsDropdownPair = H.CreateSettingsDropdownPair
    local CreateThemedCheckbox = H.CreateThemedCheckbox
    local FinalizeSettingsSectionHeight = H.FinalizeSettingsSectionHeight
    local SettingsMeasuredSectionContentHeight = H.SettingsMeasuredSectionContentHeight
    local RefreshSubtitles = H.RefreshSubtitles
    local ApplySettingsChrome = H.ApplySettingsChrome
    local ApplySettingsAccentChromeIdle = H.ApplySettingsAccentChromeIdle
    local WireSettingsAccentButtonHover = H.WireSettingsAccentButtonHover
    local RegisterSettingsAccentChrome = H.RegisterSettingsAccentChrome
    local SettingsControlChromeHover = H.SettingsControlChromeHover
    local Settings_ShowWrappedTooltip = H.Settings_ShowWrappedTooltip
    local FormatFontScaleWarningText = H.FormatFontScaleWarningText
    local sliderElements = H.sliderElements
    local themePresetButtons = H.themePresetButtons
    local themeTextRefs = H.themeTextRefs
    local parent = ctx.parent
    local effectiveWidth = ctx.effectiveWidth
    local sideInset = ctx.sideInset
    local yOffset = ctx.yOffset
    local skipPanelIntro = ctx.skipPanelIntro
    local AnchorSectionTop = ctx.AnchorSectionTop

    -- THEME & APPEARANCE
    yOffset = AppendSettingsPanelIntro(parent, "appearance", effectiveWidth, yOffset, sideInset, skipPanelIntro)
    local themeSection = CreateSection(parent, nil, effectiveWidth)
    AnchorSectionTop(themeSection, yOffset)

    local themeContentW = GetSettingsSectionContentWidth(effectiveWidth)
    local themeStackY = 0
    local warningText  -- typography panel (slider callback)

    themeStackY = StackSettingsSubPanel(themeSection.content, themeContentW, 0, function(inner, iw)
        local cy = 0
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_THEME_APPEARANCE"]) or "Appearance",
            iw, cy, { skipGapBefore = true, subtitleBright = true })

        cy = CreateDropdownWidget(inner, {
            name = (ns.L and ns.L["UI_CHROME"]) or "UI Style",
            desc = (ns.L and ns.L["UI_CHROME_TOOLTIP"]) or "Modern uses Warband Nexus custom chrome. Classic uses default Blizzard UI buttons and frames.",
            stackBelowLabel = true,
            valueOrder = { "modern", "classic" },
            values = {
                modern = (ns.L and ns.L["UI_CHROME_MODERN"]) or "Modern",
                classic = (ns.L and ns.L["UI_CHROME_CLASSIC"]) or "Classic",
            },
            get = function()
                local p = WarbandNexus.db.profile
                if p.uiTheme == "classic" or p.themeMode == "classic" then
                    return "classic"
                end
                return "modern"
            end,
            set = function(_, value)
                local p = WarbandNexus.db.profile
                local wasClassic = (p.uiTheme == "classic" or p.themeMode == "classic")
                if value == "classic" then
                    if p.uiTheme ~= "classic" and p.themeMode ~= "classic" then
                        local modernMode = (p.modernColorMode == "light" or p.themeMode == "light") and "light" or "dark"
                        p.modernColorMode = modernMode
                    end
                    p.uiTheme = "classic"
                    if p.themeMode == "classic" then
                        p.themeMode = p.modernColorMode or "dark"
                    end
                else
                    p.uiTheme = "modern"
                    local restore = (p.modernColorMode == "light") and "light" or "dark"
                    p.themeMode = restore
                    p.modernColorMode = restore
                end
                local isClassic = (p.uiTheme == "classic")
                if wasClassic ~= isClassic then
                    -- Classic chrome is baked in at widget-creation time across the
                    -- whole UI; a live toggle leaves mixed chrome. Reload rebuilds
                    -- cleanly (SavedVariables are flushed by the reload itself).
                    if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
                    return
                end
                if WarbandNexus.RefreshTheme then
                    WarbandNexus:RefreshTheme()
                elseif ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
                RefreshSubtitles()
            end,
        }, cy)

        local profileClassicChrome = function()
            local p = WarbandNexus.db.profile
            return p.uiTheme == "classic" or p.themeMode == "classic"
        end

        if not profileClassicChrome() then
        cy = CreateDropdownWidget(inner, {
            name = (ns.L and ns.L["THEME_MODE"]) or "Appearance",
            desc = (ns.L and ns.L["THEME_MODE_TOOLTIP"]) or "Dark or light surfaces for Modern UI only.",
            stackBelowLabel = true,
            valueOrder = { "dark", "light" },
            values = {
                dark = (ns.L and ns.L["THEME_MODE_DARK"]) or "Dark",
                light = (ns.L and ns.L["THEME_MODE_LIGHT"]) or "Light",
            },
            get = function()
                local p = WarbandNexus.db.profile
                if p.modernColorMode == "light" or p.themeMode == "light" then
                    return "light"
                end
                return "dark"
            end,
            set = function(_, value)
                if value ~= "light" then value = "dark" end
                local p = WarbandNexus.db.profile
                p.uiTheme = "modern"
                p.themeMode = value
                p.modernColorMode = value
                if WarbandNexus.RefreshTheme then
                    WarbandNexus:RefreshTheme()
                elseif ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
                RefreshSubtitles()
            end,
        }, cy)
        else
            local hintFs = FontManager:CreateFontString(inner, "body", "OVERLAY")
            hintFs:SetPoint("TOPLEFT", 0, cy)
            hintFs:SetWidth(iw)
            hintFs:SetJustifyH("LEFT")
            hintFs:SetWordWrap(true)
            hintFs:SetText((ns.L and ns.L["THEME_MODE_TOOLTIP"]) or "Dark or light surfaces when UI Style is Modern. Classic uses Blizzard default chrome only.")
            ns.UI_SetTextColorRole(hintFs, "Muted")
            cy = cy - math.max(18, hintFs:GetStringHeight()) - GetHeaderToolbarGap()
        end

        cy = CreateSliderWidget(inner, {
            name = (ns.L and ns.L["SHELL_BACKGROUND_OPACITY"]) or "Window Background Opacity",
            desc = (ns.L and ns.L["SHELL_BACKGROUND_OPACITY_DESC"]) or "Adjust how solid the main addon window background appears (Classic UI).",
            min = 0.2,
            max = 1.0,
            step = 0.05,
            get = function()
                if ns.UI_GetShellBackgroundOpacity then
                    return ns.UI_GetShellBackgroundOpacity()
                end
                return WarbandNexus.db.profile.shellBackgroundOpacity or 1.0
            end,
            set = function(_, value)
                value = math.floor(value * 20 + 0.5) / 20
                WarbandNexus.db.profile.shellBackgroundOpacity = value
                if WarbandNexus.mainFrame and ns.UI_RefreshMainShellChrome then
                    ns.UI_RefreshMainShellChrome(WarbandNexus.mainFrame)
                end
                if WarbandNexus.RefreshTheme then
                    WarbandNexus:RefreshTheme()
                elseif ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
                RefreshSubtitles()
            end,
            valueFormat = function(v) return string.format("%d%%", v * 100) end,
        }, cy, sliderElements)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_THEME_COLORS"]) or "Colors & Accent",
            iw, cy, { subtitleBright = true })

        local pickerH = math.max(SETTINGS_BTN_H + 6, 38)
        local colorPickerBtn = ns.UI.Factory:CreateButton(inner, math.min(280, iw), pickerH, false)
        colorPickerBtn:SetPoint("TOPLEFT", 0, cy)
    colorPickerBtn:Enable()
    
    if ApplySettingsChrome then
        ApplySettingsAccentChromeIdle(colorPickerBtn)
    end
    WireSettingsAccentButtonHover(colorPickerBtn)
    RegisterSettingsAccentChrome(colorPickerBtn)
    
    -- Button text
    local btnText = FontManager:CreateFontString(colorPickerBtn, "body", "OVERLAY")
    btnText:SetPoint("CENTER")
    btnText:SetText((ns.L and ns.L["OPEN_COLOR_PICKER"]) or "Open Color Picker")
    btnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    
    -- Click handler - Opens WoW's native color picker
    -- Apply color only when user closes picker (not while dragging) to avoid performance loss
    colorPickerBtn:SetScript("OnClick", function(self)
        local currentColor = WarbandNexus.db.profile.themeColors.accent
        local r, g, b = currentColor[1], currentColor[2], currentColor[3]
        local pendingR, pendingG, pendingB = r, g, b
        local cancelled = false
        
        local function ApplyPending()
            local colors = ns.UI_CalculateThemeColors(pendingR, pendingG, pendingB)
            WarbandNexus.db.profile.themeColors = colors
            if ns.UI_RefreshColors then
                ns.UI_RefreshColors()
            end
            RefreshSubtitles()
        end
        
        local info = {
            swatchFunc = function()
                -- Only store; apply on close (no live refresh while dragging)
                if ColorPickerFrame then
                    pendingR, pendingG, pendingB = ColorPickerFrame:GetColorRGB()
                end
            end,
            hasOpacity = false,
            opacity = 1.0,
            r = r,
            g = g,
            b = b,
            cancelFunc = function(previousValues)
                cancelled = true
                if previousValues then
                    pendingR, pendingG, pendingB = previousValues.r, previousValues.g, previousValues.b
                end
            end,
        }
        
        -- TAINT FIX: Install color picker preview hooks lazily (first open)
        -- This handles live preview + cancel/revert automatically via Config.lua hooks
        if ns.InstallColorPickerPreviewHook then
            ns.InstallColorPickerPreviewHook()
        end
        
        if not ColorPickerFrame then return end
        
        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetFrameLevel(500)
        
        -- TAINT FIX: Do NOT use SetScript("OnHide") on ColorPickerFrame.
        -- That REPLACES Blizzard's handler with tainted addon code, propagating taint.
        -- Instead, use the info table's cancelFunc callback for cancel detection,
        -- and a short-lived ticker to detect when the picker closes for confirmation.
        if ColorPickerFrame.SetupColorPickerAndShow then
            -- TWW 10.2.5+ color picker: uses info table callbacks
            info.cancelFunc = function(previousValues)
                cancelled = true
                if previousValues then
                    pendingR, pendingG, pendingB = previousValues.r, previousValues.g, previousValues.b
                end
                ApplyPending()
            end
            info.swatchFunc = function()
                if ColorPickerFrame then
                    pendingR, pendingG, pendingB = ColorPickerFrame:GetColorRGB()
                end
            end
            
            ColorPickerFrame:SetupColorPickerAndShow(info)
            
            -- Poll-based closure detection instead of hooking OnHide
            -- Avoids taint from modifying Blizzard frame script handlers
            local closeTicker = C_Timer.NewTicker(0.1, function(ticker)
                if not ColorPickerFrame:IsShown() then
                    ticker:Cancel()
                    if not cancelled then
                        ApplyPending()
                    end
                end
            end)
        else
            -- Legacy color picker (pre-10.2.5 fallback)
            ColorPickerFrame.func = info.swatchFunc
            ColorPickerFrame.opacityFunc = info.swatchFunc
            ColorPickerFrame.cancelFunc = function()
                info.cancelFunc({r = r, g = g, b = b})
            end
            ColorPickerFrame.hasOpacity = info.hasOpacity
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame.previousValues = {r = r, g = g, b = b}
            ColorPickerFrame:Show()
        end
        
        ColorPickerFrame:Raise()
    end)

        -- Hover effects
        colorPickerBtn:SetScript("OnEnter", function(self)
            if ApplySettingsChrome then
                ApplySettingsChrome(colorPickerBtn, SettingsControlChromeHover(), { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1 })
            end
            ns.UI_SetTextColorRole(btnText, "Bright")

            Settings_ShowWrappedTooltip(self, (ns.L and ns.L["COLOR_PICKER_TOOLTIP"]) or "Open WoW's native color picker wheel to choose a custom theme color")
        end)

        colorPickerBtn:SetScript("OnLeave", function(self)
            ApplySettingsAccentChromeIdle(colorPickerBtn)
            btnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
            GameTooltip:Hide()
        end)

        cy = cy - pickerH - GetHeaderToolbarGap()

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["PRESET_THEMES"]) or "Preset Themes",
            iw, cy, { subtitleBright = true })

        local themeButtons = {
        {
            label = (ns.L and ns.L["COLOR_PURPLE"]) or "Purple",
            tooltip = (ns.L and ns.L["COLOR_PURPLE_DESC"]) or "Classic purple theme (default)",
            color = {0.40, 0.20, 0.58},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.40, 0.20, 0.58)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = (ns.L and ns.L["COLOR_BLUE"]) or "Blue",
            tooltip = (ns.L and ns.L["COLOR_BLUE_DESC"]) or "Cool blue theme",
            color = {0.30, 0.65, 1.0},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.30, 0.65, 1.0)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = (ns.L and ns.L["COLOR_GREEN"]) or "Green",
            tooltip = (ns.L and ns.L["COLOR_GREEN_DESC"]) or "Nature green theme",
            color = {0.32, 0.79, 0.40},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.32, 0.79, 0.40)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = (ns.L and ns.L["COLOR_RED"]) or "Red",
            tooltip = (ns.L and ns.L["COLOR_RED_DESC"]) or "Fiery red theme",
            color = {1.0, 0.34, 0.34},
            func = function()
                local colors = ns.UI_CalculateThemeColors(1.0, 0.34, 0.34)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = (ns.L and ns.L["COLOR_ORANGE"]) or "Orange",
            tooltip = (ns.L and ns.L["COLOR_ORANGE_DESC"]) or "Warm orange theme",
            color = {1.0, 0.65, 0.30},
            func = function()
                local colors = ns.UI_CalculateThemeColors(1.0, 0.65, 0.30)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = (ns.L and ns.L["COLOR_CYAN"]) or "Cyan",
            tooltip = (ns.L and ns.L["COLOR_CYAN_DESC"]) or "Bright cyan theme",
            color = {0.00, 0.80, 1.00},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.00, 0.80, 1.00)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        }

        cy = CreateButtonGrid(inner, themeButtons, cy, iw, 120, themePresetButtons)
        cy = cy - GetHeaderToolbarGap()

        local classAccentCb = CreateThemedCheckbox(inner)
        classAccentCb:SetPoint("TOPLEFT", SETTINGS_CHECKBOX_GRID_INDENT, cy)
        local classAccentTip = (ns.L and ns.L["USE_CLASS_COLOR_ACCENT_TOOLTIP"]) or "Use your current character's class color for accents, borders, and tabs. Falls back to your saved theme color when the class cannot be resolved."
        local classAccentLbl = FontManager:CreateFontString(inner, "body", "OVERLAY")
        classAccentLbl:SetPoint("TOPLEFT", classAccentCb, "TOPRIGHT", UI_SPACING.AFTER_ELEMENT, 0)
        classAccentLbl:SetWidth(math.max(120, iw - SETTINGS_CHECKBOX_GRID_INDENT - (ns.UI_TOGGLE_SIZE or 16) - UI_SPACING.AFTER_ELEMENT))
        classAccentLbl:SetJustifyH("LEFT")
        classAccentLbl:SetWordWrap(true)
        classAccentLbl:SetText((ns.L and ns.L["USE_CLASS_COLOR_ACCENT"]) or "Use class color as accent")
        ns.UI_SetTextColorRole(classAccentLbl, "Bright")
        classAccentCb:SetChecked(WarbandNexus.db.profile.useClassColorAccent)
        if classAccentCb.checkTexture then
            classAccentCb.checkTexture:SetShown(WarbandNexus.db.profile.useClassColorAccent)
        end
        classAccentCb:SetScript("OnClick", function(self)
            local v = self:GetChecked()
            WarbandNexus.db.profile.useClassColorAccent = v
            if self.checkTexture then self.checkTexture:SetShown(v) end
            if ns.UI_RefreshColors then ns.UI_RefreshColors() end
            RefreshSubtitles()
        end)
        classAccentCb:SetScript("OnEnter", function(self)
            Settings_ShowWrappedTooltip(self, classAccentTip)
        end)
        classAccentCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        classAccentLbl:SetScript("OnEnter", function(self)
            Settings_ShowWrappedTooltip(self, classAccentTip)
        end)
        classAccentLbl:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local classRowH = math.max(ns.UI_TOGGLE_SIZE or 22, classAccentLbl:GetStringHeight(), SETTINGS_BTN_H - 6)
        cy = cy - classRowH - GetHeaderToolbarGap()

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_THEME_TYPOGRAPHY"]) or "Fonts & Readability",
            iw, cy, { subtitleBright = true })

        local fontFamilyOpt = {
        name = (ns.L and ns.L["FONT_FAMILY"]) or "Font Family",
        desc = (ns.L and ns.L["FONT_FAMILY_TOOLTIP"]) or "Choose the font used throughout the addon UI",
        values = function()
            return (ns.GetFilteredFontOptions and ns.GetFilteredFontOptions()) or {
                ["Friz Quadrata TT"] = "Friz Quadrata TT",
                ["Arial Narrow"] = "Arial Narrow",
                ["Skurri"] = "Skurri",
                ["Morpheus"] = "Morpheus",
                ["Action Man"] = "Action Man",
                ["Continuum Medium"] = "Continuum Medium",
                ["Expressway"] = "Expressway",
            }
        end,
        get = function() return WarbandNexus.db.profile.fonts.fontFace end,
        set = function(_, value)
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM and LSM.IsValid and LSM.MediaType and not LSM:IsValid(LSM.MediaType.FONT, value) then
                value = "Friz Quadrata TT"
            end
            WarbandNexus.db.profile.fonts.fontFace = value
            if ns.FontManager and ns.FontManager.RefreshAllFonts then
                ns.FontManager:RefreshAllFonts()
            end
            C_Timer.After(0.3, function()
                C_Timer.After(0.1, function()
                    if settingsFrame and settingsFrame:IsShown() then
                        if ns.WindowManager then
                            ns.WindowManager:Unregister(settingsFrame)
                        end
                        settingsFrame:Hide()
                        settingsFrame = nil
                        if WarbandNexus and WarbandNexus.ShowSettings then
                            WarbandNexus:ShowSettings()
                        end
                    end
                end)
            end)
        end,
        }

        local fontOutlineOpt = {
            name = (ns.L and ns.L["ANTI_ALIASING"]) or "Font Outline",
            desc = (ns.L and ns.L["ANTI_ALIASING_DESC"]) or "Adds a thin border around text so labels stay readable on light backgrounds and colored text.",
            values = {
                none = (ns.L and ns.L["AA_NONE"]) or "Off (smooth)",
                OUTLINE = (ns.L and ns.L["AA_OUTLINE"]) or "Outline (default)",
                THICKOUTLINE = (ns.L and ns.L["AA_THICKOUTLINE"]) or "Thick outline",
            },
            get = function() return WarbandNexus.db.profile.fonts.antiAliasing end,
            set = function(_, value)
                WarbandNexus.db.profile.fonts.antiAliasing = value
                if ns.FontManager and ns.FontManager.RefreshAllFonts then
                    ns.FontManager:RefreshAllFonts()
                end
            end,
        }

        cy = CreateSettingsDropdownPair(inner, fontFamilyOpt, fontOutlineOpt, cy, iw)

        local aaHint = FontManager:CreateFontString(inner, "small", "OVERLAY")
        aaHint:SetWidth(iw)
        aaHint:SetJustifyH("LEFT")
        aaHint:SetWordWrap(true)
        aaHint:SetPoint("TOPLEFT", 0, cy)
        aaHint:SetText((ns.L and ns.L["ANTI_ALIASING_HINT"]) or "Outline helps gold and class-colored text on pale panels. Off keeps smooth edges on dark mode.")
        ns.UI_SetTextColorRole(aaHint, "Muted")
        themeTextRefs.aaHintText = aaHint
        local aaHintH = math.max(14, aaHint:GetStringHeight())
        cy = cy - aaHintH - GetHeaderToolbarGap()

        warningText = FontManager:CreateFontString(inner, "small", "OVERLAY")
        warningText:SetWidth(iw)
        warningText:SetJustifyH("LEFT")
        warningText:SetWordWrap(true)
        themeTextRefs.warningText = warningText
        warningText:SetText(FormatFontScaleWarningText())
        warningText:Hide()

        cy = CreateSliderWidget(inner, {
            name = (ns.L and ns.L["FONT_SCALE"]) or "Font Scale",
            desc = (ns.L and ns.L["FONT_SCALE_TOOLTIP"]) or "Adjust font size across all UI elements",
            min = 0.8,
            max = 1.5,
            step = 0.1,
            get = function() return WarbandNexus.db.profile.fonts.scaleCustom or 1.0 end,
            set = function(_, value)
                WarbandNexus.db.profile.fonts.scaleCustom = value
                WarbandNexus.db.profile.fonts.useCustomScale = true
                if value > 1.0 then
                    warningText:Show()
                else
                    warningText:Hide()
                end
                if ns.FontManager and ns.FontManager.RefreshAllFonts then
                    ns.FontManager:RefreshAllFonts()
                end
            end,
        }, cy, sliderElements)

        local gapTypo = GetHeaderToolbarGap()
        local warnTop = cy - gapTypo
        warningText:SetPoint("TOPLEFT", 0, warnTop)

        local currentScale = WarbandNexus.db.profile.fonts.scaleCustom or 1.0
        if currentScale > 1.0 then
            warningText:Show()
        else
            warningText:Hide()
        end

        local warnH = (warningText:IsShown() and math.max(14, warningText:GetStringHeight())) or 0
        cy = warnTop - warnH - (warnH > 0 and gapTypo or math.floor(gapTypo / 2))

        cy = CreateCheckboxGrid(inner, {
            {
                key = "usePixelNormalization",
                label = (ns.L and ns.L["RESOLUTION_NORMALIZATION"]) or "Auto-Scale for Resolution",
                tooltip = (ns.L and ns.L["RESOLUTION_NORMALIZATION_TOOLTIP"]) or "Adjust font sizes for your monitor resolution (4K vs 1080p). WoW UI Scale still scales text with the rest of the interface.",
                get = function() return WarbandNexus.db.profile.fonts.usePixelNormalization end,
                set = function(value)
                    WarbandNexus.db.profile.fonts.usePixelNormalization = value
                    if ns.FontManager and ns.FontManager.RefreshAllFonts then
                        ns.FontManager:RefreshAllFonts()
                    end
                    C_Timer.After(0.1, function()
                        if settingsFrame and settingsFrame:IsShown() then
                            if ns.WindowManager then
                                ns.WindowManager:Unregister(settingsFrame)
                            end
                            settingsFrame:Hide()
                            settingsFrame = nil
                            WarbandNexus:ShowSettings()
                        end
                    end)
                end,
            },
        }, cy, iw, { gridTailPad = 4 })

        return cy
    end, { flat = true, noTrailingGap = true })

    local themeSectionHeight = SettingsMeasuredSectionContentHeight(themeStackY)
    FinalizeSettingsSectionHeight(themeSection, themeSectionHeight, false)
    
    -- Move to next section
    yOffset = yOffset - themeSection:GetHeight() - SETTINGS_SECTION_GAP
    return yOffset
end
