--[[
    Warband Nexus - Settings UI
    Standardized grid-based settings with event-driven architecture
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager

local issecretvalue = issecretvalue

-- LibDBIcon reference for minimap lock
local LDBI = LibStub("LibDBIcon-1.0", true)

-- Import SharedWidgets
local COLORS = ns.UI_COLORS or {accent = {0.40, 0.20, 0.58, 1}, accentDark = {0.28, 0.14, 0.41, 1}, border = {0.20, 0.20, 0.25, 1}, bg = {0.04, 0.04, 0.05, 0.98}, bgCard = {0.04, 0.04, 0.05, 0.98}, textBright = {1,1,1,1}, textNormal = {0.85,0.85,0.85,1}, textDim = {0.55,0.55,0.55,1}, white = {1,1,1,1}}
local ApplyVisuals = ns.UI_ApplyVisuals

--- Skip ApplyVisuals on Blizzard template widgets (classic UIPanelButtonTemplate, etc.).
local function ApplySettingsChrome(frame, bg, border)
    if not frame then return end
    if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(frame) then return end
    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() and ns.UI.Factory and ns.UI.Factory.ApplyBorder then
        ns.UI.Factory:ApplyBorder(frame, { tier = "thin", bgColor = bg })
        return
    end
    if ApplyVisuals then
        ApplyVisuals(frame, bg, border)
    end
end
-- Tab chrome: route all panel/card fills through ApplySettingsChrome (not raw ApplyVisuals).
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateSection = ns.UI_CreateSection

-- CONSTANTS

-- Import UI spacing constants
local UI_SPACING = ns.UI_SPACING or {
    TOP_MARGIN = 8,
    SECTION_SPACING = 8,
    SIDE_MARGIN = 10,
    MIN_BOTTOM_SPACING = 20,
    AFTER_ELEMENT = 8,
}

local MIN_ITEM_WIDTH = 180  -- Minimum width for grid items
local GRID_SPACING = UI_SPACING.SIDE_MARGIN  -- Horizontal spacing between grid items
-- Vertical gap between major settings cards (slightly larger than UI_SPACING for clearer hierarchy)
local SETTINGS_SECTION_GAP = math.max((UI_SPACING.SECTION_SPACING or 8) + 12, 20)
local SETTINGS_DIVIDER_PAD = 8
local CONTENT_PADDING_TOP = 40  -- Title height (from CreateSection standard, settings-specific)
local SETTINGS_UNTITLED_SECTION_TOP_PAD = 16
local SETTINGS_PANEL_INTRO_GAP = 14
local CONTENT_PADDING_BOTTOM = UI_SPACING.MIN_BOTTOM_SPACING  -- Bottom padding within section
-- Tighter foot room under section.content than generic MIN_BOTTOM_SPACING (avoids huge empty card bottoms)
local SETTINGS_CARD_OUTER_BOTTOM_PAD = math.min(CONTENT_PADDING_BOTTOM or 20, 10)

local UI_CONSTANTS = ns.UI_CONSTANTS or {}
local SETTINGS_BTN_H = UI_CONSTANTS.BUTTON_HEIGHT or 32
local SETTINGS_SUBSECTION_ROW_H = 24
-- Inner padding for bordered settings sub-panels (Factory container + border)
local SETTINGS_SUBPANEL_PAD = 14
-- Extra px below subsection title row before first control (added to HEADER_TOOLBAR_CONTROL_GAP / AFTER_ELEMENT)
local SETTINGS_SUBSECTION_GAP_AFTER_EXTRA = 6
-- Extra px between stacked bordered sub-panels (added to toolbar gap)
local SETTINGS_STACKED_SUBPANEL_GAP_EXTRA = 8
-- Checkbox grids: align with tab row indent; slightly taller rows reduce wrap collisions
local SETTINGS_CHECKBOX_GRID_INDENT = UI_SPACING.BASE_INDENT or 15
-- Extra X indent for rows with parentKey (single-column stacks like Advanced)
local SETTINGS_CHECKBOX_CHILD_INDENT = 22
local SETTINGS_CHECKBOX_MIN_COL_W = 268
-- Legacy minimum; checkbox rows now size to content (see CELL_MIN_H / dynamic packing).
local SETTINGS_CHECKBOX_MIN_ROW_H = 40
local SETTINGS_CHECKBOX_COL_GAP = UI_SPACING.CARD_GAP or UI_SPACING.AFTER_ELEMENT or 8
-- Dropdown rows: label column vs control (prevents long titles overlapping the control)
local SETTINGS_DROPDOWN_LABEL_COL_MIN = 176
local SETTINGS_DROPDOWN_LABEL_COL_MAX = 310
local SETTINGS_DROPDOWN_CONTROL_MIN_W = 136
-- Content frame height follows layout math.abs(stackY) exactly (card chrome uses CONTENT_PADDING_*).
local SETTINGS_CARD_CONTENT_BOTTOM_PAD = 0
-- Height for secondary controls (notification actions, try-counter helper, track lookup)
local SETTINGS_COMPACT_BTN_H = 30
-- Minimum block height for notification anchor summary (two logical lines)
local SETTINGS_ANCHOR_DESC_MIN_HEIGHT = 44
-- Embedded settings host insets (single source for DrawSettingsTab + BuildSettings)
local SETTINGS_SECTION_CARD_PAD_X = UI_SPACING.SECTION_CARD_PADDING_X or 15
local SETTINGS_LAYOUT = {
    HOST_SIDE_INSET = UI_SPACING.SETTINGS_HOST_SIDE_INSET or 10,
    HOST_TOP_INSET = UI_SPACING.SETTINGS_HOST_TOP_INSET or (UI_SPACING.TOP_MARGIN or 8),
    SECTION_CARD_PAD_X = SETTINGS_SECTION_CARD_PAD_X,
}

local function GetSettingsSectionCardWidth(containerWidth, sideInset)
    local w = containerWidth or 640
    sideInset = sideInset or 0
    if sideInset > 0 then
        w = w - (2 * sideInset)
    end
    return math.max(200, w)
end

local function GetSettingsSectionContentWidth(cardWidth)
    local px = SETTINGS_LAYOUT.SECTION_CARD_PAD_X
    return math.max(120, (cardWidth or 640) - (2 * px))
end

local function GetHeaderToolbarGap()
    local L = ns.UI_LAYOUT or UI_SPACING
    return (L and L.HEADER_TOOLBAR_CONTROL_GAP) or UI_SPACING.AFTER_ELEMENT or 8
end

local function GetStackedSubPanelTrailingGap()
    return GetHeaderToolbarGap() + SETTINGS_STACKED_SUBPANEL_GAP_EXTRA
end

--- Sync themed checkbox visual (CreateThemedCheckbox uses innerDot, not checkTexture).
local function SyncSettingsCheckboxChecked(checkbox, checked)
    if not checkbox then return end
    checkbox:SetChecked(checked)
    if checkbox.innerDot then
        checkbox.innerDot:SetShown(checked)
    elseif checkbox.checkTexture then
        checkbox.checkTexture:SetShown(checked)
    end
end

--- Lua 5.1: `for` loop `local actionId` is a single slot; factory captures one id per option.
local function MakeLauncherLeftClickCheckboxOption(keyPrefix, actionId, def, isSelectedFn, applyFn)
    return {
        key = keyPrefix .. actionId,
        label = (ns.L and ns.L[def.settingsLabelKey]) or def.labelFallback or actionId,
        tooltip = (def.settingsDescKey and ns.L and ns.L[def.settingsDescKey]) or def.labelFallback or "",
        _wnActionId = actionId,
        get = function() return isSelectedFn(actionId) end,
        set = function(value) applyFn(actionId, value) end,
    }
end

local function WireLauncherLeftClickCheckbox(widget, actionId, applyFn, syncFn)
    if not widget or not widget.checkbox or not actionId or not applyFn then return end
    -- Radio-style: always select this action (avoid GetChecked() false -> revert to toggle/pve).
    widget.checkbox:SetScript("OnClick", function()
        applyFn(actionId, true)
        if syncFn then syncFn() end
    end)
end

local function SettingsMeasuredSectionContentHeight(stackY)
    return math.abs(stackY) + SETTINGS_CARD_CONTENT_BOTTOM_PAD
end

local function SettingsSectionTopPad(hasTitle)
    if hasTitle then return CONTENT_PADDING_TOP end
    return SETTINGS_UNTITLED_SECTION_TOP_PAD
end

local function FinalizeSettingsSectionHeight(section, contentHeight, hasTitle)
    local topPad = SettingsSectionTopPad(hasTitle)
    section:SetHeight(contentHeight + topPad + SETTINGS_CARD_OUTER_BOTTOM_PAD)
    section.content:SetHeight(contentHeight)
end

---Lead copy above a panel card (panel description from SettingsUI shell).
---FontStrings are Regions, not Frames: BuildSettings' GetChildren() sweep never
---collects them, so this MUST reuse one cached instance per parent — creating a
---fresh one each rebuild leaves stale copies painted over the new layout.
local function AppendSettingsPanelIntro(parent, panelId, width, yOffset, sideInset, skipIntro)
    if skipIntro then
        if parent._wnSettingsIntroFs then
            parent._wnSettingsIntroFs:Hide()
        end
        return yOffset
    end
    local SUI = ns.SettingsUI
    local desc = SUI and SUI.PanelDescription and SUI.PanelDescription(panelId)
    if not desc or desc == "" then return yOffset end
    local fs = parent._wnSettingsIntroFs
    if not fs then
        fs = FontManager:CreateFontString(parent, "body", "OVERLAY")
        parent._wnSettingsIntroFs = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", sideInset, yOffset)
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -sideInset, yOffset)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(desc)
    ns.UI_SetTextColorRole(fs, "Dim")
    fs:Show()
    local sh = (fs.GetStringHeight and fs:GetStringHeight()) or 36
    return yOffset - math.max(18, sh) - SETTINGS_PANEL_INTRO_GAP
end

---Advance layout cy past a TOPLEFT-anchored wrapped FontString plus trailing gap.
local function AdvancePastWrappedFontString(fs, cy, gapAfter)
    if not fs then return cy end
    gapAfter = gapAfter or GetHeaderToolbarGap()
    local sh = (fs.GetStringHeight and fs:GetStringHeight()) or 18
    return cy - math.max(18, sh) - gapAfter
end

-- Scroll area vertical inset (matches SharedWidgets scroll content padding)
local SETTINGS_SCROLL_INSET_TOP = UI_SPACING.SCROLL_CONTENT_TOP_PADDING or UI_SPACING.TOP_MARGIN
local SETTINGS_SCROLL_INSET_BOTTOM = UI_SPACING.SCROLL_CONTENT_BOTTOM_PADDING or UI_SPACING.TOP_MARGIN

---Thin horizontal rule between logical settings groups (Factory theme divider).
local function AppendSettingsGroupDivider(parent, width, yOffset)
    yOffset = yOffset - SETTINGS_DIVIDER_PAD
    local bar
    if ns.UI.Factory and ns.UI.Factory.CreateThemeDivider then
        bar = ns.UI.Factory:CreateThemeDivider(parent, {
            orientation = "horizontal",
            variant = "section",
            thickness = 2,
        })
        if bar then
            bar:SetWidth(width)
            bar:SetPoint("TOPLEFT", 0, yOffset)
        end
    else
        bar = ns.UI.Factory:CreateContainer(parent, width, 2, false)
        if bar then
            bar:SetPoint("TOPLEFT", 0, yOffset)
            ApplySettingsChrome(bar,
                { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.22 },
                { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.10 })
        end
    end
    return yOffset - 2 - SETTINGS_DIVIDER_PAD
end

-- Forward declaration: BuildSettings / keybind capture.
local settingsFrame = nil
local settingsKeybindStopListening = nil
local settingsKeybindIsListening = false
local settingsKeybindButton = nil
local settingsKeybindCaptureFrame = nil

---Chat debug (Lua 5.1): only when WarbandNexus.db.profile.debugMode is true (Config → Debug Mode).
local function SettingsEscDebug(msg, ...)
    local W = WarbandNexus
    local db = W and W.db and W.db.profile
    if not (db and db.debugMode) then return end
    if not (W and W.Print) then return end
    local text
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, msg, ...)
        text = ok and s or tostring(msg)
    else
        text = tostring(msg)
    end
    W:Print("|cff00ccff[WN Settings ESC]|r " .. text)
end
-- ESC: Do NOT use SetOverrideBinding* on ESC for this panel. On current clients the API can report
-- success while the synthetic CLICK never reaches an addon Button — ESC is then swallowed and
-- ToggleGameMenu / UISpecialFrames never run. Close path: WindowManager + ToggleGameMenu / CloseAllWindows / CloseSpecialWindows hooks (settings root does NOT use InstallESCHandler — see below).
local LEGACY_ESC_PROXY_NAME = "WarbandNexusSettingsEscProxy"

---Strip any stale ESC overrides (upgrades + other code paths); does not install new overrides.
local function EnsureSettingsEscBindingsCleared()
    if InCombatLockdown() then return end
    if not ClearOverrideBindings then return end
    local panel = _G.WarbandNexusSettingsPanel
    if not panel or not panel:IsShown() then return end
    pcall(ClearOverrideBindings, panel)
    local legacy = _G[LEGACY_ESC_PROXY_NAME]
    if legacy then
        pcall(ClearOverrideBindings, legacy)
    end
    SettingsEscDebug("ESC: hooks-only mode (cleared stale override bindings on panel)")
end

local function ClearSettingsEscOverride()
    if not ClearOverrideBindings then return end
    SettingsEscDebug("ClearSettingsEscOverride()")
    local panel = _G.WarbandNexusSettingsPanel
    if panel then
        pcall(ClearOverrideBindings, panel)
    end
    local legacy = _G[LEGACY_ESC_PROXY_NAME]
    if legacy then
        pcall(ClearOverrideBindings, legacy)
    end
end

-- Post-hook: Blizzard ESC / CloseSpecialWindows path must hide the panel even if UISpecialFrames order fails.
local settingsCloseSpecialHooked = false
local function EnsureSettingsCloseSpecialHook()
    if settingsCloseSpecialHooked or type(hooksecurefunc) ~= "function" then return end
    settingsCloseSpecialHooked = true
    hooksecurefunc("CloseSpecialWindows", function()
        if ns._wnEscJustHandled then return end
        local p = _G.WarbandNexusSettingsPanel
        if p and p:IsShown() then
            SettingsEscDebug("CloseSpecialWindows post-hook → Hide()")
            p:Hide()
            return
        end
        local mf = _G.WarbandNexusFrame
        if mf and mf:IsShown() and mf.currentTab == "settings" and mf.ActivateMainTab then
            local back = mf._wnTabBeforeSettings or "chars"
            mf:ActivateMainTab(back, { persistLastTab = false })
        end
    end)
end

---Long setting tooltips: use SetText wrap flag + minimum width so text breaks into lines.
---@param owner Region
---@param text string|nil
local function Settings_ShowWrappedTooltip(owner, text)
    if not owner or not text or type(text) ~= "string" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    local w = 340
    if owner.GetParent then
        local parent = owner:GetParent()
        if parent and parent.GetWidth then
            local pw = parent:GetWidth()
            if pw and pw > 120 then
                w = math.max(260, math.min(440, pw - 40))
            end
        end
    end
    if GameTooltip.SetMinimumWidth then
        GameTooltip:SetMinimumWidth(w)
    end
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local SettingsKeybind = ns.SettingsKeybind

-- GRID LAYOUT SYSTEM

---Apply disabled visual state to a checkbox + label pair
---@param checkbox CheckButton The checkbox widget
---@param label FontString The label widget
---@param disabled boolean Whether to disable (true) or enable (false)
local function SetCheckboxDisabled(checkbox, label, disabled)
    if disabled then
        checkbox:Disable()
        checkbox:SetAlpha(0.35)
        ns.UI_SetTextColorRole(label, "Dim", 0.6)
    else
        checkbox:Enable()
        checkbox:SetAlpha(1.0)
        ns.UI_SetTextColorRole(label, "Bright")
    end
end

local function SetCheckboxRowHidden(checkbox, label, hidden)
    if hidden then
        checkbox:Hide()
        label:Hide()
    else
        checkbox:Show()
        label:Show()
    end
end

---Create grid-based checkbox layout (RESPONSIVE - auto-adjusts columns)
---Supports hierarchical parent-child dependencies via option.parentKey.
---When a parent checkbox is unchecked, all descendants are recursively
---disabled and non-clickable. Supports multi-level chains (e.g. A → B → C).
---@param parent Frame Parent container
---@param options table Array of {key, label, tooltip, get, set, parentKey?}
---@param yOffset number Starting Y offset
---@param explicitWidth number Optional explicit width (bypasses GetWidth)
---@param gridOpts table|nil Optional { maxColumns, minColumns, childIndent, indentChildren, gridTailPad }
---  Nested indent: parentKey + indentChildren (default: only when numCols == 1); indentChildren=false disables.
---  Rows stack by measured checkbox/label height (no fixed 40px slab).
---@return number newYOffset, table widgets (keyed by option.key → {checkbox, label})
local function CreateCheckboxGrid(parent, options, yOffset, explicitWidth, gridOpts)
    gridOpts = gridOpts or {}
    -- Responsive fixed-column grid: column count grows with available width.
    -- All items in a given column share the same X anchor → perfect alignment.
    local containerWidth = explicitWidth or parent:GetWidth() or 640

    -- Determine column count based on width (prefer readability over density).
    -- 1-2 columns keeps long labels from looking cramped in Settings.
    local MIN_COL_WIDTH = SETTINGS_CHECKBOX_MIN_COL_W
    local COL_SPACING = SETTINGS_CHECKBOX_COL_GAP
    local rowIndent = SETTINGS_CHECKBOX_GRID_INDENT
    local usableWidth = math.max(120, containerWidth - rowIndent)
    local layoutMaxCols = gridOpts.maxColumns
    if layoutMaxCols then
        layoutMaxCols = math.max(1, math.min(3, math.floor(tonumber(layoutMaxCols) or 1)))
    else
        layoutMaxCols = 2
    end
    if gridOpts.minColWidth and tonumber(gridOpts.minColWidth) then
        MIN_COL_WIDTH = math.max(160, math.floor(tonumber(gridOpts.minColWidth)))
    end
    local numCols = math.floor((usableWidth + COL_SPACING) / (MIN_COL_WIDTH + COL_SPACING))
    numCols = math.max(1, math.min(layoutMaxCols, numCols))
    local minColsReq = tonumber(gridOpts.minColumns)
    if minColsReq and minColsReq > 1 then
        numCols = math.max(numCols, math.min(layoutMaxCols, math.floor(minColsReq)))
    end
    local colWidth = (usableWidth - (COL_SPACING * (numCols - 1))) / numCols
    local defaultChildIndent = SETTINGS_CHECKBOX_CHILD_INDENT

    local CELL_MIN_H = math.max(20, (ns.UI_TOGGLE_SIZE or 22))
    local ROW_GAP = math.max(4, math.floor(((UI_SPACING.AFTER_ELEMENT or 8)) * 0.75))

    local widgets = {}       -- key → {checkbox, label}
    local optionByKey = {}   -- key → option
    local childKeys = {}     -- parentKey → {childKey1, childKey2, ...}
    local parentKeyMap = {}  -- childKey → parentKey

    local packRow = -1
    local rowTopY = yOffset
    local rowMaxH = CELL_MIN_H
    local yCursor = yOffset

    for i = 1, #options do
        local option = options[i]
        local col = (i - 1) % numCols
        local row = math.floor((i - 1) / numCols)

        if row ~= packRow then
            if packRow >= 0 then
                yCursor = rowTopY - rowMaxH - ROW_GAP
            end
            packRow = row
            rowTopY = yCursor
            rowMaxH = CELL_MIN_H
        end

        local indentExtra = 0
        local wantChildIndent = gridOpts.indentChildren
        if wantChildIndent == nil then
            wantChildIndent = (numCols == 1)
        end
        if option.parentKey and wantChildIndent then
            indentExtra = (gridOpts.childIndent ~= nil) and gridOpts.childIndent or defaultChildIndent
        end
        local xPos = rowIndent + indentExtra + col * (colWidth + COL_SPACING)
        xPos = math.floor(xPos + 0.5)
        local yPos = rowTopY

        local checkbox = CreateThemedCheckbox(parent)
        checkbox:SetPoint("TOPLEFT", xPos, yPos)

        -- Label: TOPLEFT from toggle TOPRIGHT so multi-line wraps predictably and aligns with 16px toggles
        local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
        label:SetJustifyH("LEFT")
        label:SetText(option.label)
        ns.UI_SetTextColorRole(label, "Bright")
        label:SetPoint("TOPLEFT", checkbox, "TOPRIGHT", UI_SPACING.AFTER_ELEMENT, 1)
        -- Constrain label width (reserve nested indent so text stays inside the card)
        local toggleW = (ns.UI_TOGGLE_SIZE or 16)
        local labelW = colWidth - toggleW - UI_SPACING.AFTER_ELEMENT - indentExtra
        label:SetWidth(math.max(80, labelW))
        label:SetWordWrap(true)

        -- Set initial value
        if option.get then
            checkbox:SetChecked(option.get())
            if checkbox.checkTexture then
                checkbox.checkTexture:SetShown(option.get())
            end
        end

        -- Store widget reference
        if option.key then
            widgets[option.key] = { checkbox = checkbox, label = label }
            optionByKey[option.key] = option
            if gridOpts.externalWidgets then
                gridOpts.externalWidgets[option.key] = widgets[option.key]
            end
        end

        -- Build dependency tree
        if option.parentKey and option.key then
            parentKeyMap[option.key] = option.parentKey
            childKeys[option.parentKey] = childKeys[option.parentKey] or {}
            table.insert(childKeys[option.parentKey], option.key)
        end

        -- Tooltip on hover
        if option.tooltip then
            checkbox:SetScript("OnEnter", function(self)
                Settings_ShowWrappedTooltip(self, option.tooltip)
            end)
            checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)

            label:SetScript("OnEnter", function(self)
                Settings_ShowWrappedTooltip(self, option.tooltip)
            end)
            label:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        local ch = checkbox:GetHeight() or CELL_MIN_H
        local lh = label:GetStringHeight() or CELL_MIN_H
        -- +1 matches TOPRIGHT/TOPLEFT vertical nudge so wrapped labels don’t clip the next row
        rowMaxH = math.max(rowMaxH, math.max(ch, lh + 1))
    end
    
    local externalWidgets = gridOpts.externalWidgets

    local function ResolveCheckboxWidget(key)
        if not key then return nil end
        local w = widgets[key]
        if w then return w end
        if externalWidgets then
            return externalWidgets[key]
        end
        return nil
    end

    -- Check if a key has any ancestor that is unchecked (recursive)
    local function IsAnyAncestorUnchecked(key)
        local pKey = parentKeyMap[key]
        if not pKey then return false end
        local parentWidget = ResolveCheckboxWidget(pKey)
        if not parentWidget then return false end
        if not parentWidget.checkbox:GetChecked() then return true end
        return IsAnyAncestorUnchecked(pKey)
    end
    
    local function ApplyHideChildrenWhenOff(parentKey, parentChecked)
        local parentOption = optionByKey[parentKey]
        if not parentOption or not parentOption.hideChildrenWhenOff then return end
        local kids = childKeys[parentKey]
        if not kids then return end
        for ki = 1, #kids do
            local w = widgets[kids[ki]]
            if w then
                SetCheckboxRowHidden(w.checkbox, w.label, not parentChecked)
                if not parentChecked then
                    SetCheckboxDisabled(w.checkbox, w.label, true)
                end
            end
        end
    end

    -- Recursively cascade enable/disable to all descendants of a key
    local function CascadeDescendants(key, forceDisable)
        local kids = childKeys[key]
        if not kids then return end
        for ki = 1, #kids do
            local childKey = kids[ki]
            local w = widgets[childKey]
            if w then
                if forceDisable then
                    -- Parent chain is broken → disable regardless of own state
                    SetCheckboxDisabled(w.checkbox, w.label, true)
                    CascadeDescendants(childKey, true)
                else
                    -- Parent chain is active → enable this child
                    SetCheckboxDisabled(w.checkbox, w.label, false)
                    -- Continue cascade: grandchildren depend on whether THIS child is checked
                    local childUnchecked = not w.checkbox:GetChecked()
                    CascadeDescendants(childKey, childUnchecked)
                end
            end
        end
    end

    -- Synchronize descendant checkbox state + DB values when a parent is toggled.
    -- This enforces true hierarchical behavior:
    -- parent OFF -> all descendants OFF
    -- parent ON  -> all descendants ON (children can still be manually changed later)
    local function SyncDescendantsCheckedState(key, newState)
        local kids = childKeys[key]
        if not kids then return end

        for ki = 1, #kids do
            local childKey = kids[ki]
            local w = widgets[childKey]
            local childOption = optionByKey[childKey]
            if w then
                local current = not not w.checkbox:GetChecked()
                if current ~= newState then
                    w.checkbox:SetChecked(newState)
                    if w.checkbox.checkTexture then
                        w.checkbox.checkTexture:SetShown(newState)
                    end
                    if childOption and childOption.set then
                        childOption.set(newState)
                    end
                elseif w.checkbox.checkTexture then
                    -- Keep visual marker in sync even when state already matches.
                    w.checkbox.checkTexture:SetShown(newState)
                end

                SyncDescendantsCheckedState(childKey, newState)
            end
        end
    end
    
    -- Set OnClick handlers (needs CascadeDescendants to be defined)
    for i = 1, #options do
        local option = options[i]
        if option.key and widgets[option.key] then
            local cb = widgets[option.key].checkbox
            cb:SetScript("OnClick", function(self)
                local isChecked = self:GetChecked()
                if option.set then
                    option.set(isChecked)
                end
                
                if self.checkTexture then
                    self.checkTexture:SetShown(isChecked)
                end
                
                -- Recursive cascade to all descendants
                if option.key then
                    if not option.skipChildSync then
                        SyncDescendantsCheckedState(option.key, isChecked)
                    end
                    if option.hideChildrenWhenOff then
                        ApplyHideChildrenWhenOff(option.key, isChecked)
                    end
                    CascadeDescendants(option.key, not isChecked)
                end
                
                -- Notify external dependents (sliders, buttons, etc.)
                if widgets._onParentToggle then
                    widgets._onParentToggle(option.key, isChecked)
                end
            end)
        end
    end
    
    -- Apply initial disabled state: walk the tree top-down
    -- Process root options first, then cascade within this grid
    for oi = 1, #options do
        local option = options[oi]
        if option.key and not option.parentKey and widgets[option.key] then
            if not widgets[option.key].checkbox:GetChecked() then
                CascadeDescendants(option.key, true)
            else
                CascadeDescendants(option.key, false)
            end
        end
    end
    -- Parents in another grid (e.g. notifications master toggle) still gate children here
    for oi = 1, #options do
        local option = options[oi]
        if option.key and option.parentKey and widgets[option.key] then
            if IsAnyAncestorUnchecked(option.key) then
                SetCheckboxDisabled(widgets[option.key].checkbox, widgets[option.key].label, true)
                CascadeDescendants(option.key, true)
            end
        end
    end
    for oi = 1, #options do
        local option = options[oi]
        if option.hideChildrenWhenOff and option.key and widgets[option.key] then
            ApplyHideChildrenWhenOff(option.key, widgets[option.key].checkbox:GetChecked())
            if widgets[option.key].checkbox:GetChecked() then
                CascadeDescendants(option.key, false)
            end
        end
    end

    local gridTailPad = gridOpts.gridTailPad or (UI_SPACING.AFTER_ELEMENT or 8)
    if #options == 0 then
        return yOffset - gridTailPad, widgets
    end
    if packRow >= 0 then
        yCursor = rowTopY - rowMaxH - ROW_GAP
    end
    -- No trailing ROW_GAP after last row (ROW_GAP already accounted before last yCursor advance)
    return yCursor + ROW_GAP - gridTailPad, widgets
end

-- Declared before CreateButtonGrid: Lua locals are not visible before their definition line.
local function SettingsControlChrome()
    return ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop() or { 0.08, 0.08, 0.10, 1 }
end

local function SettingsControlChromeHover()
    return ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop() or { 0.12, 0.12, 0.14, 1 }
end

local function ColorNearMatch(rgbA, rgbB, eps)
    eps = eps or 0.035
    if not rgbA or not rgbB then return false end
    return math.abs(rgbA[1] - rgbB[1]) <= eps
        and math.abs(rgbA[2] - rgbB[2]) <= eps
        and math.abs(rgbA[3] - rgbB[3]) <= eps
end

local function GetCurrentThemeAccentRgb()
    local db = WarbandNexus.db and WarbandNexus.db.profile
    local ac = (db and db.themeColors and db.themeColors.accent) or COLORS.accent
    return ac[1], ac[2], ac[3]
end

local function IsThemePresetSelected(presetColor)
    local r, g, b = GetCurrentThemeAccentRgb()
    return ColorNearMatch({ r, g, b }, presetColor)
end

local function ApplyThemePresetButtonChrome(entry, isSelected)
    if not entry or not entry.button then return end
    local btnColor = entry.color
    local btn = entry.button
    if btn._wnBlizzardButton then
        if ns.UI_ApplyClassicNavTabActiveState then
            ns.UI_ApplyClassicNavTabActiveState(btn, isSelected)
        end
    else
        local bg
        if isSelected then
            if ns.UI_IsLightMode and ns.UI_IsLightMode() then
                local ta = (ns.UI_COLORS or COLORS).tabActive
                if ta then
                    bg = { ta[1], ta[2], ta[3], ta[4] or 0.98 }
                else
                    bg = SettingsControlChromeHover()
                end
            else
                bg = (ns.UI_GetAccentListeningBackdrop and ns.UI_GetAccentListeningBackdrop()) or SettingsControlChromeHover()
            end
        else
            bg = SettingsControlChrome()
        end
        local borderA = isSelected and 1.0 or 0.8
        ApplySettingsChrome(btn, bg, { btnColor[1], btnColor[2], btnColor[3], borderA })
    end
    if entry.text then
        if isSelected and btn._wnBlizzardButton then
            local gr, gg, gb = btnColor[1], btnColor[2], btnColor[3]
            if ns.UI_GetSemanticGoldColor then
                gr, gg, gb = ns.UI_GetSemanticGoldColor()
            end
            entry.text:SetTextColor(gr, gg, gb)
        else
            entry.text:SetTextColor(btnColor[1], btnColor[2], btnColor[3])
        end
    end
end

---Create button grid (RESPONSIVE - auto-adjusts columns)
---@param parent Frame Parent container
---@param buttons table Array of {label, tooltip, func, color (optional {r,g,b})}
---@param yOffset number Starting Y offset
---@param explicitWidth number Optional explicit width
---@param minButtonWidth number Optional minimum button width (default: MIN_ITEM_WIDTH)
---@param presetRegistry table|nil Optional registry for theme preset grid ({ button, text, color })
---@return number New Y offset after grid
local function CreateButtonGrid(parent, buttons, yOffset, explicitWidth, minButtonWidth, presetRegistry)
    -- Calculate dynamic columns
    local containerWidth = explicitWidth or parent:GetWidth() or 640
    local minWidth = minButtonWidth or MIN_ITEM_WIDTH  -- Use custom min width if provided
    local itemsPerRow = math.max(2, math.floor((containerWidth + GRID_SPACING) / (minWidth + GRID_SPACING)))
    local buttonWidth = (containerWidth - (GRID_SPACING * (itemsPerRow - 1))) / itemsPerRow
    local buttonHeight = SETTINGS_BTN_H
    
    local row = 0
    local col = 0
    
    for i = 1, #buttons do
        local btnData = buttons[i]
        -- Create button
        local button = ns.UI.Factory:CreateButton(parent)
        button:SetSize(buttonWidth, buttonHeight)
        
        -- Position in grid
        local xPos = col * (buttonWidth + GRID_SPACING)
        button:SetPoint("TOPLEFT", xPos, yOffset + (row * -(buttonHeight + UI_SPACING.AFTER_ELEMENT)))
        button:Enable()
        
        -- Use button's own color if provided, otherwise use theme accent
        local btnColor = btnData.color or {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}
        local isPreset = presetRegistry ~= nil
        local isSelected = isPreset and IsThemePresetSelected(btnColor)

        if not isPreset then
            ApplySettingsChrome(button, SettingsControlChrome(), { btnColor[1], btnColor[2], btnColor[3], 0.8 })
        end
        
        -- Button text
        local buttonText = FontManager:CreateFontString(button, "body", "OVERLAY")
        buttonText:SetPoint("CENTER")
        buttonText:SetText(btnData.label)
        buttonText:SetTextColor(btnColor[1], btnColor[2], btnColor[3])

        if isPreset then
            ApplyThemePresetButtonChrome({ button = button, text = buttonText, color = btnColor }, isSelected)
            presetRegistry[#presetRegistry + 1] = { button = button, text = buttonText, color = btnColor }
        end
        
        -- OnClick
        button:SetScript("OnClick", function()
            if btnData.func then
                btnData.func()
            end
        end)
        
        -- Hover effects
        button:SetScript("OnEnter", function(self)
            if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(button) then
                ns.UI_SetTextColorRole(buttonText, "Bright")
            else
                ApplySettingsChrome(button, SettingsControlChromeHover(), { btnColor[1], btnColor[2], btnColor[3], 1 })
                ns.UI_SetTextColorRole(buttonText, "Bright")
            end
            
            if btnData.tooltip then
                Settings_ShowWrappedTooltip(self, btnData.tooltip)
            end
        end)
        
        button:SetScript("OnLeave", function(self)
            if isPreset then
                ApplyThemePresetButtonChrome({ button = button, text = buttonText, color = btnColor }, IsThemePresetSelected(btnColor))
            else
                ApplySettingsChrome(button, SettingsControlChrome(), { btnColor[1], btnColor[2], btnColor[3], 0.8 })
                buttonText:SetTextColor(btnColor[1], btnColor[2], btnColor[3])
            end
            GameTooltip:Hide()
        end)
        
        -- Move to next grid position
        col = col + 1
        if col >= itemsPerRow then
            col = 0
            row = row + 1
        end
    end
    
    -- Calculate total height used
    local totalRows = math.ceil(#buttons / itemsPerRow)
    return yOffset - (totalRows * (buttonHeight + UI_SPACING.AFTER_ELEMENT)) - 15
end

-- WIDGET BUILDERS

---Close another open settings dropdown (UIParent-level click-catcher can sit above scroll content and steal clicks).
local function CloseOtherSettingsDropdownForClick(currentDropdown)
    if ns._wnSettingsOpenDropdownMenu and ns._wnSettingsOpenDropdownMenu:IsShown()
        and ns._wnSettingsOpenDropdownOwner
        and ns._wnSettingsOpenDropdownOwner ~= currentDropdown
    then
        ns._wnSettingsOpenDropdownMenu:Hide()
    end
    if ns._wnSettingsDropdownClickCatcher and ns._wnSettingsOpenDropdownOwner
        and ns._wnSettingsOpenDropdownOwner ~= currentDropdown
    then
        ns._wnSettingsDropdownClickCatcher:Hide()
    end
end

---@return boolean closed
function ns.UI_CloseSettingsOpenDropdown()
    if not ns._wnSettingsOpenDropdownMenu or not ns._wnSettingsOpenDropdownMenu:IsShown() then
        return false
    end
    ns._wnSettingsOpenDropdownMenu:Hide()
    if ns._wnSettingsDropdownClickCatcher then
        ns._wnSettingsDropdownClickCatcher:Hide()
    end
    ns._wnSettingsOpenDropdownMenu = nil
    ns._wnSettingsOpenDropdownOwner = nil
    ns._wnSettingsDropdownClickCatcher = nil
    return true
end

-- Settings controls that use accent borders (dropdown triggers, chrome buttons, inputs).
-- Declared before CreateDropdownWidget / CreateInputWidget: Lua locals are not visible before their line.
local settingsAccentChrome = {}

local function ApplySettingsAccentChromeIdle(btn)
    if not btn then return end
    local C = ns.UI_COLORS or COLORS
    local a = C.accent or COLORS.accent
    local bg = ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop() or { 0.08, 0.08, 0.10, 1 }
    local borderA = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.55 or 0.75
    ApplySettingsChrome(btn, bg, { a[1], a[2], a[3], borderA })
end

local function WireSettingsAccentButtonHover(btn)
    if not btn then return end
    btn:SetScript("OnEnter", function(self)
        local C = ns.UI_COLORS or COLORS
        local a = C.accent or COLORS.accent
        local hover = ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop() or { 0.12, 0.12, 0.14, 1 }
        ApplySettingsChrome(self, hover, { a[1], a[2], a[3], 1 })
    end)
    btn:SetScript("OnLeave", function(self)
        ApplySettingsAccentChromeIdle(self)
    end)
end

local function RegisterSettingsAccentChrome(btn)
    if btn then
        settingsAccentChrome[#settingsAccentChrome + 1] = btn
    end
end

local function RefreshSettingsAccentChrome()
    for i = 1, #settingsAccentChrome do
        local f = settingsAccentChrome[i]
        if f and f:IsShown() then
            ApplySettingsAccentChromeIdle(f)
        end
    end
end

local function SettingsDropdownMenuBg()
    return ns.UI_GetDropdownMenuBackdrop and ns.UI_GetDropdownMenuBackdrop() or SettingsControlChrome()
end

local function SettingsNestedCardBg()
    if ns.UI_GetNestedCardBackdrop then
        return ns.UI_GetNestedCardBackdrop()
    end
    local c = ns.UI_COLORS or COLORS
    local card = c.bgCard or c.bg
    return { card[1], card[2], card[3], (card[4] or 1) * 0.92 }
end

local function SettingsDialogShellBg()
    return ns.UI_GetExternalShellBackdrop and ns.UI_GetExternalShellBackdrop() or SettingsDropdownMenuBg()
end

local function AccentInlineHex()
    local ac = (ns.UI_COLORS or COLORS).accent
    return string.format("|cff%02x%02x%02x", ac[1] * 255, ac[2] * 255, ac[3] * 255)
end

---Create dropdown widget
---@param option table may include stackBelowLabel (force label row + control row)
local function CreateDropdownWidget(parent, option, yOffset)
    local pw = parent:GetWidth() or 400
    local gap = GetHeaderToolbarGap()
    local labelColW = math.min(SETTINGS_DROPDOWN_LABEL_COL_MAX,
        math.max(SETTINGS_DROPDOWN_LABEL_COL_MIN, math.floor(pw * 0.40)))
    local controlW = pw - labelColW - gap
    -- stackBelowLabel: label full width on first row, dropdown below (avoids wide settings rows).
    local useStacked = option.stackBelowLabel == true or controlW < SETTINGS_DROPDOWN_CONTROL_MIN_W
    if useStacked then
        controlW = pw
    end

    -- Label
    local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    local optionName = type(option.name) == "function" and option.name() or option.name
    label:SetText(optionName)
    ns.UI_SetTextColorRole(label, "Bright")

    -- Dropdown button
    local dropdown = ns.UI.Factory:CreateButton(parent)
    dropdown:SetHeight(SETTINGS_BTN_H)
    dropdown:SetWidth(math.max(SETTINGS_DROPDOWN_CONTROL_MIN_W, controlW))

    local labelH = 18
    if useStacked then
        label:SetPoint("TOPLEFT", 0, yOffset)
        label:SetWidth(pw)
        labelH = math.max(18, label:GetStringHeight())
        dropdown:SetPoint("TOPLEFT", 0, yOffset - labelH - gap)
        dropdown:SetWidth(pw)
    else
        label:SetPoint("TOPLEFT", 0, yOffset)
        label:SetWidth(labelColW)
        labelH = math.max(18, label:GetStringHeight())
        dropdown:SetPoint("TOPLEFT", labelColW + gap, yOffset)
    end

    ApplySettingsAccentChromeIdle(dropdown)
    WireSettingsAccentButtonHover(dropdown)
    RegisterSettingsAccentChrome(dropdown)

    -- Tooltip
    if option.desc then
        label:SetScript("OnEnter", function(self)
            local desc = type(option.desc) == "function" and option.desc() or option.desc
            Settings_ShowWrappedTooltip(self, desc)
        end)
        label:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    dropdown:EnableMouse(true)
    -- LeftButtonUp only: avoids double OnClick and stops the click-catcher from seeing a paired down/up in the same open action.
    if dropdown.RegisterForClicks then
        dropdown:RegisterForClicks("LeftButtonUp")
    end

    local valueText = FontManager:CreateFontString(dropdown, "body", "OVERLAY")
    valueText:SetPoint("LEFT", 12, 0)
    valueText:SetPoint("RIGHT", -32, 0)
    valueText:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(valueText, "Bright")
    if valueText.EnableMouse then valueText:EnableMouse(false) end
    
    -- Arrow icon
    local arrow = dropdown:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -12, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetTexCoord(0, 1, 0, 1)
    
    -- Get values function
    local function GetValues()
        if not option.values then return nil end
        return type(option.values) == "function" and option.values() or option.values
    end
    
    -- Update display (resilient: fallback so font names don't disappear after refresh)
    local function UpdateDisplay()
        local values = GetValues()
        if not values then
            valueText:SetText((ns.L and ns.L["NO_OPTIONS"]) or "No Options")
            return
        end
        
        if option.get then
            local currentValue = option.get()
            local display = (currentValue and values[currentValue])
                or (currentValue and type(currentValue) == "string" and not (issecretvalue and issecretvalue(currentValue)) and currentValue:match("[^\\/]+$"))  -- filename from path
                or (currentValue and tostring(currentValue))
                or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
            valueText:SetText(display)
        else
            valueText:SetText((ns.L and ns.L["NONE_LABEL"]) or "None")
        end
    end
    
    UpdateDisplay()
    
    -- Dropdown menu
    local activeMenu = nil
    
    if parent and parent.EnableMouse then parent:EnableMouse(true) end

    dropdown:SetScript("OnClick", function(self)
        CloseOtherSettingsDropdownForClick(dropdown)

        local values = GetValues()
        if not values then return end

        -- Parent menus to the settings window so UIParent-level hit layers do not sit above scroll content.
        local menuParent = (_G.WarbandNexusFrame and _G.WarbandNexusFrame:IsShown() and _G.WarbandNexusFrame) or UIParent

        -- Toggle
        if activeMenu and activeMenu:IsShown() then
            activeMenu:Hide()
            activeMenu = nil
            return
        end
        
        if activeMenu then
            activeMenu:Hide()
            activeMenu = nil
        end
        
        local menuWidth = dropdown:GetWidth()
        
        -- Build ordered option rows (valueOrder keeps logical order; else sort by display text)
        local sortedOptions = {}
        if option.valueOrder then
            for i = 1, #option.valueOrder do
                local key = option.valueOrder[i]
                local displayText = values[key]
                if displayText ~= nil then
                    sortedOptions[#sortedOptions + 1] = { value = key, text = displayText }
                end
            end
            for value, displayText in pairs(values) do
                local seen
                for j = 1, #sortedOptions do
                    if sortedOptions[j].value == value then
                        seen = true
                        break
                    end
                end
                if not seen then
                    sortedOptions[#sortedOptions + 1] = { value = value, text = displayText }
                end
            end
        else
            for value, displayText in pairs(values) do
                sortedOptions[#sortedOptions + 1] = { value = value, text = displayText }
            end
            table.sort(sortedOptions, function(a, b) return a.text < b.text end)
        end
        
        local itemHeight = 28
        local rowCount = #sortedOptions

        -- Reuse existing menu if available (Factory container for standard compliance)
        local menu = dropdown._dropdownMenu
        if not menu then
            menu = ns.UI.Factory:CreateContainer(menuParent, 200, 300, true)
            if menu then
                menu:SetFrameStrata("FULLSCREEN_DIALOG")
                menu:SetFrameLevel(300)
                menu:SetClampedToScreen(true)
                if ApplySettingsChrome then
                    local menuBg = SettingsDropdownMenuBg()
                    ApplySettingsChrome(menu, menuBg, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
                end
            end
            dropdown._dropdownMenu = menu
        else
            menu:SetParent(menuParent)
        end
        if not menu then return end

        menu:SetWidth(menuWidth)
        if option.menuOpensUpward then
            menu:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
        else
            menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
        end
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        local baseLvl = (menuParent.GetFrameLevel and menuParent:GetFrameLevel()) or 0
        menu:SetFrameLevel(baseLvl + 100)
        menu:Raise()
        if not InCombatLockdown() then
            if menu.EnableKeyboard then menu:EnableKeyboard(true) end
            if menu.SetPropagateKeyboardInput then menu:SetPropagateKeyboardInput(true) end
        end

        activeMenu = menu

        local scrollFrame, scrollChild = ns.UI_ApplyDropdownScrollLayout(menu, rowCount, itemHeight)
        if scrollFrame then scrollFrame:EnableMouseWheel(true) end

        local bin = ns.UI_RecycleBin
        if scrollChild then
            local ch = { scrollChild:GetChildren() }
            for chi = 1, #ch do
                ch[chi]:Hide()
                if bin then ch[chi]:SetParent(bin) else ch[chi]:SetParent(nil) end
            end
        end

        local btnWidth = (scrollChild and scrollChild:GetWidth()) or menuWidth
        if btnWidth < 40 then btnWidth = menuWidth - 40 end

        -- Create option buttons (standardized: ApplyVisuals, consistent height, highlight current)
        local currentValue = option.get and option.get()
        local yPos = (ns.UI_LAYOUT and ns.UI_LAYOUT.DROPDOWN_INSET_TOP) or 4
        for oi = 1, #sortedOptions do
            local data = sortedOptions[oi]
            local btn = ns.UI.Factory:CreateButton(scrollChild, btnWidth, itemHeight, true)
            if not btn then break end
            btn:EnableMouse(true)
            if btn.RegisterForClicks then
                btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
            end
            btn:SetPoint("TOPLEFT", 0, -yPos)
            
            local isCurrent = (currentValue == data.value)
            local bgColor = ns.UI_GetDropdownRowBackdrop and ns.UI_GetDropdownRowBackdrop(isCurrent)
                or (isCurrent and { 0.12, 0.12, 0.16, 1 } or { 0.07, 0.07, 0.09, 1 })
            local borderColor = isCurrent and {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8} or {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.4}
            
            if ApplySettingsChrome then
                ApplySettingsChrome(btn, bgColor, borderColor)
            end
            
            local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
            btnText:SetPoint("LEFT", 10, 0)
            btnText:SetPoint("RIGHT", -10, 0)
            btnText:SetJustifyH("LEFT")
            if btnText.EnableMouse then btnText:EnableMouse(false) end
            btnText:SetText(data.text)
            
            if isCurrent then
                btnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
            else
                ns.UI_SetTextColorRole(btnText, "Bright")
            end
            
            -- Hover
            btn:SetScript("OnEnter", function(self)
                local hover = ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop() or { 0.15, 0.15, 0.18, 1 }
                if self.SetBackdropColor then self:SetBackdropColor(hover[1], hover[2], hover[3], hover[4] or 1) end
                if ns.UI_UpdateBorderColor then ns.UI_UpdateBorderColor(self, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9}) end
            end)
            btn:SetScript("OnLeave", function(self)
                if self.SetBackdropColor then self:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4]) end
                if ns.UI_UpdateBorderColor then ns.UI_UpdateBorderColor(self, borderColor) end
            end)
            
            btn:SetScript("OnClick", function()
                if option.set then
                    option.set(nil, data.value)
                    UpdateDisplay()
                end
                menu:Hide()
                activeMenu = nil
            end)
            
            yPos = yPos + itemHeight
        end

        ns.UI_ApplyDropdownScrollLayout(menu, rowCount, itemHeight)
        scrollFrame = menu._wnDropdownScroll
        scrollChild = menu._wnDropdownScrollChild
        
        menu:Show()
        
        if not InCombatLockdown() then menu:SetPropagateKeyboardInput(false) end
        menu:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if ns.UI_CloseSettingsOpenDropdown then
                    ns.UI_CloseSettingsOpenDropdown()
                else
                    if dropdown._clickCatcher then
                        dropdown._clickCatcher:Hide()
                    end
                    self:Hide()
                end
                activeMenu = nil
                ns._wnEscJustHandled = true
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function() ns._wnEscJustHandled = nil end)
                end
            end
        end)
        
        local clickCatcher = dropdown._clickCatcher
        if not clickCatcher then
            clickCatcher = ns.UI.Factory:CreateContainer(menuParent, 1, 1, false)
            if clickCatcher then
                clickCatcher:SetAllPoints(menuParent)
                clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
                clickCatcher:SetFrameLevel(math.max(0, (menu:GetFrameLevel() or 0) - 1))
                clickCatcher:EnableMouse(true)
                clickCatcher:SetScript("OnMouseUp", function(_, button)
                    if button and button ~= "LeftButton" then return end
                    menu:Hide()
                    activeMenu = nil
                    clickCatcher:Hide()
                end)
            end
            dropdown._clickCatcher = clickCatcher
        else
            clickCatcher:SetParent(menuParent)
            clickCatcher:SetAllPoints(menuParent)
            clickCatcher:SetScript("OnMouseUp", function(_, button)
                if button and button ~= "LeftButton" then return end
                menu:Hide()
                activeMenu = nil
                clickCatcher:Hide()
            end)
        end

        if not menu._clickCatcherHideHandlerInstalled then
            menu._clickCatcherHideHandlerInstalled = true
            menu:SetScript("OnHide", function()
                if ns._wnSettingsOpenDropdownMenu == menu then
                    ns._wnSettingsOpenDropdownMenu = nil
                    ns._wnSettingsOpenDropdownOwner = nil
                end
                if ns._wnSettingsDropdownClickCatcher == dropdown._clickCatcher then
                    ns._wnSettingsDropdownClickCatcher = nil
                end
                local catcher = dropdown._clickCatcher
                if catcher then
                    catcher:Hide()
                end
            end)
        end

        -- Defer catcher to next frame so the click that opened the menu is not treated as "outside".
        ns._wnSettingsOpenDropdownMenu = menu
        ns._wnSettingsOpenDropdownOwner = dropdown
        ns._wnSettingsDropdownClickCatcher = clickCatcher
        if clickCatcher then
            clickCatcher:Hide()
            C_Timer.After(0, function()
                if not dropdown._clickCatcher or dropdown._clickCatcher ~= clickCatcher then return end
                if not menu or not menu:IsShown() then return end
                clickCatcher:SetFrameStrata(menu:GetFrameStrata())
                clickCatcher:SetFrameLevel(math.max(0, (menu:GetFrameLevel() or 0) - 1))
                clickCatcher:Show()
            end)
        end
    end)

    local rowCore = useStacked and (labelH + gap + SETTINGS_BTN_H) or math.max(SETTINGS_BTN_H, labelH + 4)
    return yOffset - rowCore - gap, dropdown, label
end

--- Two dropdowns on one row (stacked labels) when wide enough; otherwise vertical stack.
local function CreateSettingsDropdownPair(parent, leftOpt, rightOpt, yOffset, innerWidth)
    local gap = GRID_SPACING
    local minPairW = 520
    leftOpt.stackBelowLabel = true
    rightOpt.stackBelowLabel = true
    if innerWidth < minPairW then
        local cy = yOffset
        cy = select(1, CreateDropdownWidget(parent, leftOpt, cy))
        cy = select(1, CreateDropdownWidget(parent, rightOpt, cy))
        return cy
    end
    local colW = math.floor((innerWidth - gap) / 2)
    local leftCol = ns.UI.Factory and ns.UI.Factory:CreateContainer(parent, colW, 1, false)
    local rightCol = ns.UI.Factory and ns.UI.Factory:CreateContainer(parent, colW, 1, false)
    if not leftCol or not rightCol then
        local cy = yOffset
        cy = select(1, CreateDropdownWidget(parent, leftOpt, cy))
        cy = select(1, CreateDropdownWidget(parent, rightOpt, cy))
        return cy
    end
    leftCol:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    rightCol:SetPoint("TOPLEFT", parent, "TOPLEFT", colW + gap, yOffset)
    local cyL = select(1, CreateDropdownWidget(leftCol, leftOpt, 0))
    local cyR = select(1, CreateDropdownWidget(rightCol, rightOpt, 0))
    local rowH = math.max(math.abs(cyL), math.abs(cyR))
    leftCol:SetHeight(rowH)
    rightCol:SetHeight(rowH)
    return yOffset - rowH - GetHeaderToolbarGap()
end

---Create styled input (EditBox) widget
---@param parent Frame Parent container
---@param option table {name, desc, width, get, set, numeric}
---@param yOffset number Starting Y offset
---@return number newYOffset
---@return EditBox editBox The created EditBox reference
local function CreateInputWidget(parent, option, yOffset)
    -- Label
    local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    label:SetPoint("TOPLEFT", 0, yOffset)
    local optionName = type(option.name) == "function" and option.name() or option.name
    label:SetText(optionName)
    ns.UI_SetTextColorRole(label, "Bright")

    -- Tooltip on label
    if option.desc then
        label:SetScript("OnEnter", function(self)
            local desc = type(option.desc) == "function" and option.desc() or option.desc
            Settings_ShowWrappedTooltip(self, desc)
        end)
        label:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- EditBox (Factory for standard compliance)
    local editBox = ns.UI.Factory:CreateEditBox(parent)
    if not editBox then return yOffset - 68, nil end
    editBox:SetHeight(30)
    local boxWidth = option.width or 200
    editBox:SetWidth(boxWidth)
    editBox:SetPoint("TOPLEFT", 0, yOffset - 22)
    editBox:SetTextInsets(10, 10, 0, 0)
    editBox:SetMaxLetters(option.maxLetters or 128)

    if option.numeric then
        editBox:SetNumeric(false) -- We handle numeric validation ourselves
    end

    ApplySettingsAccentChromeIdle(editBox)
    WireSettingsAccentButtonHover(editBox)
    RegisterSettingsAccentChrome(editBox)

    -- Set initial value
    if option.get then
        local val = option.get()
        editBox:SetText(val or "")
    end

    -- On enter pressed or focus lost → commit value
    local function CommitValue()
        if option.set then
            local t = editBox:GetText()
            if t and issecretvalue and issecretvalue(t) then
                editBox:ClearFocus()
                return
            end
            option.set(t)
        end
        editBox:ClearFocus()
    end

    editBox:SetScript("OnEnterPressed", CommitValue)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusLost", CommitValue)

    return yOffset - 68, editBox
end

---Create slider widget
---@param parent Frame Parent container
---@param option table Slider option config
---@param yOffset number Starting Y offset
---@param sliderTrackingTable table Optional table to track slider for theme refresh
---@return number New Y offset
local function CreateSliderWidget(parent, option, yOffset, sliderTrackingTable)
    -- Label with value
    local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    label:SetPoint("TOPLEFT", 0, yOffset)
    ns.UI_SetTextColorRole(label, "Bright")
    
    local optionName = type(option.name) == "function" and option.name() or option.name
    local function UpdateLabel()
        local currentValue = option.get and option.get() or (option.min or 0)
        local displayValue = (option.valueFormat and option.valueFormat(currentValue)) or string.format("%.1f", currentValue)
        label:SetText(string.format("%s: %s%s|r", optionName, AccentInlineHex(), displayValue))
    end
    
    UpdateLabel()
    
    -- Slider (single source of truth: Factory:CreateThemedSlider)
    local slider = ns.UI.Factory:CreateThemedSlider(parent, {
        min = option.min or 0,
        max = option.max or 1,
        step = option.step or 0.1,
        value = option.get and option.get() or nil,
        height = 20,
        onChange = function(value)
            if option.set then
                option.set(nil, value)  -- AceConfig pattern: (info, value)
                UpdateLabel()
            end
        end,
    })
    slider:SetPoint("TOPLEFT", 0, yOffset - 25)
    slider:SetPoint("TOPRIGHT", 0, yOffset - 25)

    -- Track slider for theme refresh (if tracking table provided)
    if sliderTrackingTable then
        table.insert(sliderTrackingTable, slider)
    end
    
    -- Tooltip
    if option.desc then
        slider:SetScript("OnEnter", function(self)
            local desc = type(option.desc) == "function" and option.desc() or option.desc
            Settings_ShowWrappedTooltip(self, desc)
        end)
        slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    return yOffset - 65
end

-- Track subtitle elements for theme refresh
local subtitleElements = {}
local sliderElements = {}
local themePresetButtons = {}
local themeWarningText = nil
local themeAaHintText = nil

local function FormatFontScaleWarningText()
    local warnHex = (ns.UI_GetSemanticWarningHex and ns.UI_GetSemanticWarningHex()) or "|cffff8800"
    return warnHex .. ((ns.L and ns.L["FONT_SCALE_WARNING"]) or "Warning: Higher font scale may cause text overflow in some UI elements.") .. "|r"
end

local function RefreshPresetThemeButtons()
    for i = 1, #themePresetButtons do
        local entry = themePresetButtons[i]
        if entry and entry.button and entry.button:IsShown() then
            ApplyThemePresetButtonChrome(entry, IsThemePresetSelected(entry.color))
        end
    end
end

local function RefreshThemeWarningText()
    if themeWarningText and themeWarningText:IsShown() then
        themeWarningText:SetText(FormatFontScaleWarningText())
    end
end

---Subsection title row: thin accent bar + title (FontManager). Updates with RefreshSubtitles unless opts.muted / subtitleBright.
local function AppendSettingsSubSectionHeader(parent, titleText, innerWidth, yOffset, opts)
    if not parent or not titleText then return yOffset end
    opts = opts or {}
    local gapBefore = opts.skipGapBefore and 0 or GetHeaderToolbarGap()
    local gapAfter = opts.skipGapAfter and 0 or (GetHeaderToolbarGap() + SETTINGS_SUBSECTION_GAP_AFTER_EXTRA)
    local rowH = SETTINGS_SUBSECTION_ROW_H
    local rowTop = yOffset - gapBefore
    local row = ns.UI.Factory:CreateContainer(parent, innerWidth, rowH, false)
    if not row then return yOffset, nil end
    row:SetPoint("TOPLEFT", 0, rowTop)
    local useClassic = ns.UI_IsClassicMode and ns.UI_IsClassicMode()
    if useClassic and ns.UI_ApplyClassicListHeaderChrome then
        local hdrBg = (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.surfaceHeaderChrome)
            or (COLORS.surfaceHeaderChrome or COLORS.bgCard)
        ns.UI_ApplyClassicListHeaderChrome(row, { hdrBg[1], hdrBg[2], hdrBg[3], hdrBg[4] or 1 })
    end
    local barW = 3
    local accentBar = row:CreateTexture(nil, "ARTWORK")
    accentBar:SetSize(barW, rowH - 8)
    accentBar:SetPoint("LEFT", 6, 0)
    local ac = COLORS.accent
    local barA = 0.92
    if opts.muted and not opts.subtitleBright then
        barA = 0.35
    elseif ns.UI_IsLightMode and ns.UI_IsLightMode() then
        barA = opts.subtitleBright and 0.62 or 0.48
    end
    if useClassic then
        accentBar:Hide()
    else
        accentBar:SetColorTexture(ac[1], ac[2], ac[3], barA)
    end
    local titleFs = FontManager:CreateFontString(row, "subtitle", "OVERLAY")
    if useClassic then
        titleFs:SetPoint("LEFT", row, "LEFT", 10, 0)
    else
        titleFs:SetPoint("LEFT", accentBar, "RIGHT", 10, 0)
    end
    titleFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetWordWrap(false)
    titleFs:SetMaxLines(1)
    titleFs:SetText(titleText)
    if opts.subtitleBright then
        ns.UI_SetTextColorRole(titleFs, "Bright")
    elseif opts.muted then
        ns.UI_SetTextColorRole(titleFs, "Dim")
    else
        titleFs:SetTextColor(ac[1], ac[2], ac[3])
        table.insert(subtitleElements, titleFs)
    end
    return rowTop - rowH - gapAfter, titleFs
end

---Stack a sub-panel inside section.content.
---opts.flat: layout only — no bordered inner card (single main CreateSection shell).
---opts.noTrailingGap: omit trailing spacer after this block (legacy; flat stacks default to 0 gap).
---opts.blockTrailingGap: optional px between stacked flat blocks (default 0 — avoid cumulative dead space).
local function StackSettingsSubPanel(hostContent, panelWidth, stackY, buildInner, opts)
    opts = opts or {}
    -- Classic: CreateSection already provides one dialog-box border; inner bordered panels stack corners.
    if not opts.flat and ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome() then
        opts.flat = true
    end
    if opts.flat then
        local anchor = ns.UI.Factory and ns.UI.Factory.CreateContainer and ns.UI.Factory:CreateContainer(hostContent, panelWidth, 1, false)
        if not anchor then
            anchor = CreateFrame("Frame", nil, hostContent)
            anchor:SetSize(panelWidth, 1)
        end
        anchor:SetPoint("TOPLEFT", hostContent, "TOPLEFT", 0, stackY)
        local iw = panelWidth
        local cy = buildInner(anchor, iw)
        local blockH = math.max(1, math.abs(cy))
        anchor:SetHeight(blockH)
        local gap = opts.noTrailingGap and 0 or (opts.blockTrailingGap or 0)
        return stackY - anchor:GetHeight() - gap
    end
    local pad = SETTINGS_SUBPANEL_PAD
    local panel = ns.UI.Factory:CreateContainer(hostContent, panelWidth, 1, true)
    if not panel then return stackY end
    panel:SetPoint("TOPLEFT", 0, stackY)
    local inner = ns.UI.Factory:CreateContainer(panel, panelWidth - 2 * pad, 1, false)
    inner:SetPoint("TOPLEFT", pad, -pad)
    local iw = inner:GetWidth()
    local cy = buildInner(inner, iw)
    local innerH = math.abs(cy) + pad
    inner:SetHeight(innerH)
    panel:SetHeight(innerH + 2 * pad)
    local gap = opts.noTrailingGap and 0 or GetStackedSubPanelTrailingGap()
    return stackY - panel:GetHeight() - gap
end

local function RefreshSubtitles()
    for si = 1, #subtitleElements do
        local subtitle = subtitleElements[si]
        if subtitle and subtitle:IsShown() then
            subtitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        end
    end
    for sli = 1, #sliderElements do
        local slider = sliderElements[sli]
        if slider and slider:IsShown() then
            if slider._wnBlizzardSlider then
                -- Classic OptionsSliderTemplate: skip custom border tint.
            else
                local thumb = slider:GetThumbTexture()
                if thumb then
                    thumb:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
                end
                if slider.SetBackdropBorderColor then
                    slider:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
                end
            end
        end
    end
    RefreshPresetThemeButtons()
    RefreshThemeWarningText()
end

-- BuildSettings closes over 60+ chunk locals if helpers are referenced directly; route via _H + in-function unpack (Lua 5.1 upvalue cap).
do
    local SUI = ns.SettingsUI or {}
    ns.SettingsUI = SUI
    SUI._H = {
        wipe = wipe,
        WarbandNexus = WarbandNexus,
        ADDON_NAME = ADDON_NAME,
        LDBI = LDBI,
        COLORS = COLORS,
        FontManager = FontManager,
        ns = ns,
        issecretvalue = issecretvalue,
        SettingsKeybind = SettingsKeybind,
        SETTINGS_LAYOUT = SETTINGS_LAYOUT,
        SETTINGS_SECTION_GAP = SETTINGS_SECTION_GAP,
        SETTINGS_SCROLL_INSET_BOTTOM = SETTINGS_SCROLL_INSET_BOTTOM,
        SETTINGS_BTN_H = SETTINGS_BTN_H,
        SETTINGS_COMPACT_BTN_H = SETTINGS_COMPACT_BTN_H,
        SETTINGS_CHECKBOX_GRID_INDENT = SETTINGS_CHECKBOX_GRID_INDENT,
        SETTINGS_ANCHOR_DESC_MIN_HEIGHT = SETTINGS_ANCHOR_DESC_MIN_HEIGHT,
        SETTINGS_CARD_OUTER_BOTTOM_PAD = SETTINGS_CARD_OUTER_BOTTOM_PAD,
        CONTENT_PADDING_TOP = CONTENT_PADDING_TOP,
        UI_SPACING = UI_SPACING,
        GetSettingsSectionCardWidth = GetSettingsSectionCardWidth,
        GetSettingsSectionContentWidth = GetSettingsSectionContentWidth,
        GetHeaderToolbarGap = GetHeaderToolbarGap,
        AppendSettingsPanelIntro = AppendSettingsPanelIntro,
        AppendSettingsSubSectionHeader = AppendSettingsSubSectionHeader,
        StackSettingsSubPanel = StackSettingsSubPanel,
        CreateSection = CreateSection,
        CreateCheckboxGrid = CreateCheckboxGrid,
        CreateDropdownWidget = CreateDropdownWidget,
        CreateSliderWidget = CreateSliderWidget,
        CreateInputWidget = CreateInputWidget,
        CreateButtonGrid = CreateButtonGrid,
        CreateSettingsDropdownPair = CreateSettingsDropdownPair,
        CreateThemedCheckbox = CreateThemedCheckbox,
        FinalizeSettingsSectionHeight = FinalizeSettingsSectionHeight,
        SettingsMeasuredSectionContentHeight = SettingsMeasuredSectionContentHeight,
        AdvancePastWrappedFontString = AdvancePastWrappedFontString,
        MakeLauncherLeftClickCheckboxOption = MakeLauncherLeftClickCheckboxOption,
        WireLauncherLeftClickCheckbox = WireLauncherLeftClickCheckbox,
        SyncSettingsCheckboxChecked = SyncSettingsCheckboxChecked,
        RefreshSubtitles = RefreshSubtitles,
        ApplySettingsChrome = ApplySettingsChrome,
        ApplySettingsAccentChromeIdle = ApplySettingsAccentChromeIdle,
        WireSettingsAccentButtonHover = WireSettingsAccentButtonHover,
        RegisterSettingsAccentChrome = RegisterSettingsAccentChrome,
        SettingsControlChrome = SettingsControlChrome,
        SettingsControlChromeHover = SettingsControlChromeHover,
        SettingsNestedCardBg = SettingsNestedCardBg,
        SettingsDialogShellBg = SettingsDialogShellBg,
        Settings_ShowWrappedTooltip = Settings_ShowWrappedTooltip,
        SetCheckboxDisabled = SetCheckboxDisabled,
        FormatFontScaleWarningText = FormatFontScaleWarningText,
        subtitleElements = subtitleElements,
        sliderElements = sliderElements,
        settingsAccentChrome = settingsAccentChrome,
        themePresetButtons = themePresetButtons,
    }
end

---@param parent Frame
---@param containerWidth number|nil
---@param layoutOpts table|nil `{ startYOffset, sideInset }` for embedded main-window tab
local function BuildSettings(parent, containerWidth, layoutOpts)
    local H = ns.SettingsUI._H
    local wipe = H.wipe
    local WarbandNexus = H.WarbandNexus
    local ADDON_NAME = H.ADDON_NAME
    local LDBI = H.LDBI
    local COLORS = H.COLORS
    local FontManager = H.FontManager
    local ns = H.ns
    local issecretvalue = H.issecretvalue
    local SettingsKeybind = H.SettingsKeybind
    local SETTINGS_LAYOUT = H.SETTINGS_LAYOUT
    local SETTINGS_SECTION_GAP = H.SETTINGS_SECTION_GAP
    local SETTINGS_SCROLL_INSET_BOTTOM = H.SETTINGS_SCROLL_INSET_BOTTOM
    local SETTINGS_BTN_H = H.SETTINGS_BTN_H
    local SETTINGS_COMPACT_BTN_H = H.SETTINGS_COMPACT_BTN_H
    local SETTINGS_CHECKBOX_GRID_INDENT = H.SETTINGS_CHECKBOX_GRID_INDENT
    local SETTINGS_ANCHOR_DESC_MIN_HEIGHT = H.SETTINGS_ANCHOR_DESC_MIN_HEIGHT
    local SETTINGS_CARD_OUTER_BOTTOM_PAD = H.SETTINGS_CARD_OUTER_BOTTOM_PAD
    local CONTENT_PADDING_TOP = H.CONTENT_PADDING_TOP
    local UI_SPACING = H.UI_SPACING
    local GetSettingsSectionCardWidth = H.GetSettingsSectionCardWidth
    local GetSettingsSectionContentWidth = H.GetSettingsSectionContentWidth
    local GetHeaderToolbarGap = H.GetHeaderToolbarGap
    local AppendSettingsPanelIntro = H.AppendSettingsPanelIntro
    local AppendSettingsSubSectionHeader = H.AppendSettingsSubSectionHeader
    local StackSettingsSubPanel = H.StackSettingsSubPanel
    local CreateSection = H.CreateSection
    local CreateCheckboxGrid = H.CreateCheckboxGrid
    local CreateDropdownWidget = H.CreateDropdownWidget
    local CreateSliderWidget = H.CreateSliderWidget
    local CreateInputWidget = H.CreateInputWidget
    local CreateButtonGrid = H.CreateButtonGrid
    local CreateSettingsDropdownPair = H.CreateSettingsDropdownPair
    local CreateThemedCheckbox = H.CreateThemedCheckbox
    local FinalizeSettingsSectionHeight = H.FinalizeSettingsSectionHeight
    local SettingsMeasuredSectionContentHeight = H.SettingsMeasuredSectionContentHeight
    local AdvancePastWrappedFontString = H.AdvancePastWrappedFontString
    local MakeLauncherLeftClickCheckboxOption = H.MakeLauncherLeftClickCheckboxOption
    local WireLauncherLeftClickCheckbox = H.WireLauncherLeftClickCheckbox
    local SyncSettingsCheckboxChecked = H.SyncSettingsCheckboxChecked
    local RefreshSubtitles = H.RefreshSubtitles
    local ApplySettingsChrome = H.ApplySettingsChrome
    local ApplySettingsAccentChromeIdle = H.ApplySettingsAccentChromeIdle
    local WireSettingsAccentButtonHover = H.WireSettingsAccentButtonHover
    local RegisterSettingsAccentChrome = H.RegisterSettingsAccentChrome
    local SettingsControlChrome = H.SettingsControlChrome
    local SettingsControlChromeHover = H.SettingsControlChromeHover
    local SettingsNestedCardBg = H.SettingsNestedCardBg
    local SettingsDialogShellBg = H.SettingsDialogShellBg
    local Settings_ShowWrappedTooltip = H.Settings_ShowWrappedTooltip
    local SetCheckboxDisabled = H.SetCheckboxDisabled
    local FormatFontScaleWarningText = H.FormatFontScaleWarningText
    local subtitleElements = H.subtitleElements
    local sliderElements = H.sliderElements
    local settingsAccentChrome = H.settingsAccentChrome
    local themePresetButtons = H.themePresetButtons

    layoutOpts = layoutOpts or {}
    -- Clear existing
    local bin = ns.UI_RecycleBin
    for _, child in pairs({parent:GetChildren()}) do
        child:Hide()
        if bin then child:SetParent(bin) else child:SetParent(nil) end
    end
    -- Region-level leftovers (GetChildren only returns Frames).
    if parent._wnSettingsIntroFs then
        parent._wnSettingsIntroFs:Hide()
    end
    
    -- Clear tracking tables
    wipe(subtitleElements)
    wipe(sliderElements)
    wipe(settingsAccentChrome)
    wipe(themePresetButtons)
    themeWarningText = nil
    themeAaHintText = nil
    
    local sideInset = layoutOpts.sideInset
    if sideInset == nil then
        sideInset = SETTINGS_LAYOUT.HOST_SIDE_INSET
    end
    local effectiveWidth = GetSettingsSectionCardWidth(containerWidth or parent:GetWidth(), sideInset)
    local yOffset = layoutOpts.startYOffset
    if yOffset == nil then
        yOffset = -SETTINGS_LAYOUT.HOST_TOP_INSET
    end
    local skipPanelIntro = layoutOpts.skipPanelIntro == true
    local function Want(panelId)
        return ns.SettingsUI and ns.SettingsUI.PanelActive(layoutOpts, panelId)
    end
    
    local function AnchorSectionTop(section, y)
        section:SetPoint("TOPLEFT", sideInset, y)
        section:SetPoint("TOPRIGHT", -sideInset, y)
    end

    if Want("general") then
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
    keybindBtnText:SetPoint("CENTER")
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
    clearIcon:SetAtlas("uitools-icon-close")
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

        cy = CreateSliderWidget(inner, {
            name = (ns.L and ns.L["UI_SCALE"]) or "UI Scale",
            desc = (ns.L and ns.L["UI_SCALE_TOOLTIP"]) or "Scale the entire addon window. Reduce if the window takes up too much screen space.",
            min = 0.6,
            max = 1.5,
            step = 0.05,
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
    end -- general panel

    if Want("modules") and ns.SettingsUI and ns.SettingsUI.AppendModulesPanel then
        yOffset = ns.SettingsUI.AppendModulesPanel({
            parent = parent,
            effectiveWidth = effectiveWidth,
            yOffset = yOffset,
            sideInset = sideInset,
            skipPanelIntro = skipPanelIntro,
            helpers = {
                AppendSettingsPanelIntro = AppendSettingsPanelIntro,
                CreateSection = CreateSection,
                AnchorSectionTop = AnchorSectionTop,
                StackSettingsSubPanel = StackSettingsSubPanel,
                AppendSettingsSubSectionHeader = AppendSettingsSubSectionHeader,
                GetHeaderToolbarGap = GetHeaderToolbarGap,
                CreateCheckboxGrid = CreateCheckboxGrid,
                SettingsMeasuredSectionContentHeight = SettingsMeasuredSectionContentHeight,
                FinalizeSettingsSectionHeight = FinalizeSettingsSectionHeight,
                SETTINGS_SECTION_GAP = SETTINGS_SECTION_GAP,
                GetSettingsSectionContentWidth = GetSettingsSectionContentWidth,
                SETTINGS_LAYOUT = SETTINGS_LAYOUT,
            },
        })
    end -- modules panel


    if Want("access") then
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
    end -- access panel

    if Want("filters") then
    -- TAB FILTERING
    yOffset = AppendSettingsPanelIntro(parent, "filters", effectiveWidth, yOffset, sideInset, skipPanelIntro)
    local tabSection = CreateSection(parent, nil, effectiveWidth)
    AnchorSectionTop(tabSection, yOffset)

    local warbandOptions = {}
    local tabFmt = (ns.L and ns.L["TAB_FORMAT"]) or "Tab %d"
    local ignoreTabFmt = (ns.L and ns.L["IGNORE_WARBAND_TAB_FORMAT"]) or "Ignore Warband Bank Tab %d from automatic scanning"
    for i = 1, 5 do
        table.insert(warbandOptions, {
            key = "tab" .. i,
            label = string.format(tabFmt, i),
            tooltip = string.format(ignoreTabFmt, i),
            get = function() return WarbandNexus.db.profile.ignoredTabs[i] end,
            set = function(value) WarbandNexus.db.profile.ignoredTabs[i] = value end,
        })
    end

    local personalBankOptions = {}
    local bankLbl = (ns.L and ns.L["BANK_LABEL"]) or "Bank"
    local bagFmt = (ns.L and ns.L["BAG_FORMAT"]) or "Bag %d"
    local ignoreScanFmt = (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) or "Ignore %s from automatic scanning"
    local personalBankLabels = {bankLbl, string.format(bagFmt, 6), string.format(bagFmt, 7), string.format(bagFmt, 8), string.format(bagFmt, 9), string.format(bagFmt, 10), string.format(bagFmt, 11)}
    local personalBankBags = ns.PERSONAL_BANK_BAGS
    for i = 1, #personalBankBags do
        local bagID = personalBankBags[i]
        local label = personalBankLabels[i] or string.format(bagFmt, bagID)
        table.insert(personalBankOptions, {
            key = "pbank" .. bagID,
            label = label,
            tooltip = string.format(ignoreScanFmt, label),
            get = function()
                if not WarbandNexus.db.profile.ignoredPersonalBankBags then
                    WarbandNexus.db.profile.ignoredPersonalBankBags = {}
                end
                return WarbandNexus.db.profile.ignoredPersonalBankBags[bagID]
            end,
            set = function(value)
                if not WarbandNexus.db.profile.ignoredPersonalBankBags then
                    WarbandNexus.db.profile.ignoredPersonalBankBags = {}
                end
                WarbandNexus.db.profile.ignoredPersonalBankBags[bagID] = value
            end,
        })
    end

    local inventoryOptions = {}
    local backpackLabel = (ns.L and ns.L["BACKPACK_LABEL"]) or "Backpack"
    local reagentLabel = (ns.L and ns.L["REAGENT_LABEL"]) or "Reagent"
    local invBagFmt = (ns.L and ns.L["BAG_FORMAT"]) or "Bag %d"
    local invIgnoreFmt = (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) or "Ignore %s from automatic scanning"
    local inventoryLabels = {backpackLabel, string.format(invBagFmt, 1), string.format(invBagFmt, 2), string.format(invBagFmt, 3), string.format(invBagFmt, 4), reagentLabel}
    local inventoryBags = ns.INVENTORY_BAGS
    for i = 1, #inventoryBags do
        local bagID = inventoryBags[i]
        local label = inventoryLabels[i] or string.format(invBagFmt, bagID)
        table.insert(inventoryOptions, {
            key = "inv" .. bagID,
            label = label,
            tooltip = string.format(invIgnoreFmt, label),
            get = function()
                if not WarbandNexus.db.profile.ignoredInventoryBags then
                    WarbandNexus.db.profile.ignoredInventoryBags = {}
                end
                return WarbandNexus.db.profile.ignoredInventoryBags[bagID]
            end,
            set = function(value)
                if not WarbandNexus.db.profile.ignoredInventoryBags then
                    WarbandNexus.db.profile.ignoredInventoryBags = {}
                end
                WarbandNexus.db.profile.ignoredInventoryBags[bagID] = value
            end,
        })
    end

    local tabInnerW = GetSettingsSectionContentWidth(effectiveWidth)
    local tabStackY = 0
    tabStackY = StackSettingsSubPanel(tabSection.content, tabInnerW, 0, function(inner, iw)
        local cy = 0
        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_TAB_WARBAND"]) or "Warband Bank",
            iw, cy, { skipGapBefore = true })
        cy = CreateCheckboxGrid(inner, warbandOptions, cy, iw)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_TAB_PERSONAL_BANK"]) or "Personal Bank",
            iw, cy)
        cy = CreateCheckboxGrid(inner, personalBankOptions, cy, iw)

        cy = AppendSettingsSubSectionHeader(inner,
            (ns.L and ns.L["SETTINGS_SECTION_TAB_INVENTORY"]) or "Inventory",
            iw, cy)
        cy = CreateCheckboxGrid(inner, inventoryOptions, cy, iw)
        return cy
    end, { flat = true, noTrailingGap = true })

    local contentHeight = SettingsMeasuredSectionContentHeight(tabStackY)
    FinalizeSettingsSectionHeight(tabSection, contentHeight, false)

    -- Move to next section
    yOffset = yOffset - tabSection:GetHeight() - SETTINGS_SECTION_GAP
    end -- filters panel

    if Want("notifications") then
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
                        dep.widget:SetTextColor(dep.color[1], dep.color[2], dep.color[3], dep.color[4] or 1)
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
    notifGridYOffset, _ = AppendSettingsSubSectionHeader(notifSection.content,
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
        dlg:Show()
    end

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

    local function closePositionGhosts()
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
        table.insert(notifExternalDependents, { type = "label", widget = durationLabel, color = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]} })
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
    local function roleRgb(role, dr, dg, db)
        if ns.UI_GetTextRoleRGB then
            local r, g, b = ns.UI_GetTextRoleRGB(role)
            return { r, g, b }
        end
        return { dr, dg, db }
    end
    table.insert(notifExternalDependents, { type = "label", widget = notifPerLaneLabel, color = roleRgb("Muted", 0.82, 0.82, 0.82) })
    table.insert(notifExternalDependents, { type = "button", widget = unifiedLayoutCheck })
    table.insert(notifExternalDependents, { type = "label", widget = unifiedLayoutLabel, color = roleRgb("Bright", 1, 1, 1) })
    table.insert(notifExternalDependents, { type = "label", widget = useAlertFrameLabel, color = {1, 1, 1} })
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
    end -- notifications panel

    if Want("appearance") then
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
        themeAaHintText = aaHint
        local aaHintH = math.max(14, aaHint:GetStringHeight())
        cy = cy - aaHintH - GetHeaderToolbarGap()

        warningText = FontManager:CreateFontString(inner, "small", "OVERLAY")
        warningText:SetWidth(iw)
        warningText:SetJustifyH("LEFT")
        warningText:SetWordWrap(true)
        themeWarningText = warningText
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
    end -- appearance panel

    if Want("advanced") then
    -- TRACK ITEM DB
    yOffset = AppendSettingsPanelIntro(parent, "advanced", effectiveWidth, yOffset, sideInset, skipPanelIntro)
    local trackSection = CreateSection(parent, (ns.L and ns.L["TRACK_ITEM_DB"]) or "Track Item DB", effectiveWidth)
    AnchorSectionTop(trackSection, yOffset)
    
    -- Collapsible: arrow + title aligned with other sections (15px left padding, same as CreateSection)
    local COLLAPSED_HEIGHT = CONTENT_PADDING_TOP  -- title bar only
    local trackIsCollapsed = true  -- default collapsed
    local HEADER_LEFT_INDENT = SETTINGS_LAYOUT.SECTION_CARD_PAD_X
    local ARROW_TITLE_GAP = 6
    
    local trackChevronBtn = ns.UI_CreateCollapseExpandControl(trackSection, not trackIsCollapsed, { enableMouse = false })
    trackChevronBtn:SetPoint("TOPLEFT", trackSection, "TOPLEFT", HEADER_LEFT_INDENT, -12)

    local titleText = trackSection.titleText
    titleText:ClearAllPoints()
    titleText:SetPoint("LEFT", trackChevronBtn, "RIGHT", ARROW_TITLE_GAP, 0)
    titleText:SetPoint("RIGHT", trackSection, "RIGHT", -HEADER_LEFT_INDENT, 0)
    titleText:SetPoint("TOP", trackChevronBtn, "TOP")
    titleText:SetPoint("BOTTOM", trackChevronBtn, "BOTTOM")
    
    local collapseBtn = ns.UI.Factory:CreateButton(trackSection, 1, 24, true)
    if collapseBtn then
        collapseBtn:SetPoint("TOPLEFT", trackChevronBtn, "TOPLEFT")
        collapseBtn:SetPoint("BOTTOMRIGHT", titleText, "BOTTOMRIGHT")
    end
    
    local trackYOffset = 0
    local trackContentWidth = GetSettingsSectionContentWidth(effectiveWidth)
    
    -- SUB-PANEL: Item Tracking
    
    local manageHeader = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    manageHeader:SetPoint("TOPLEFT", 0, trackYOffset)
    manageHeader:SetText("|cffffcc00" .. ((ns.L and ns.L["MANAGE_ITEMS"]) or "Item Tracking") .. "|r")
    trackYOffset = trackYOffset - 20
    
    -- Build unique item list from CollectibleSourceDB
    local itemRegistry = {}   -- { [key] = { name, type, itemID, repeatable, guaranteed, sources } }
    local dropdownValues = {} -- { [key] = "Display Name" }
    
    local function RegisterDrop(drop, sourceType, sourceID)
        if not drop or not drop.itemID or not drop.name then return end
        local key = (drop.type or "item") .. ":" .. drop.itemID
        if not itemRegistry[key] then
            itemRegistry[key] = {
                name = drop.name,
                type = drop.type or "item",
                itemID = drop.itemID,
                repeatable = drop.repeatable or false,
                guaranteed = drop.guaranteed or false,
                sources = {},
            }
            local typeLabel = ""
            if drop.type == "mount" then
                typeLabel = "|cff00ccff[" .. ((ns.L and ns.L["TYPE_MOUNT"]) or "Mount") .. "]|r "
            elseif drop.type == "pet" then
                typeLabel = "|cff44ff44[" .. ((ns.L and ns.L["TYPE_PET"]) or "Pet") .. "]|r "
            elseif drop.type == "toy" then
                typeLabel = "|cffff8800[" .. ((ns.L and ns.L["TYPE_TOY"]) or "Toy") .. "]|r "
            elseif drop.type == "illusion" then
                typeLabel = "|cffcc66ff[" .. ((ns.L and ns.L["TYPE_ILLUSION"]) or "Illusion") .. "]|r "
            else
                typeLabel = "|cff888888[" .. ((ns.L and ns.L["TYPE_ITEM"]) or "Item") .. "]|r "
            end
            dropdownValues[key] = typeLabel .. drop.name
        end
        local sources = itemRegistry[key].sources
        local found = false
        for si = 1, #sources do
            local s = sources[si]
            if s.sourceType == sourceType and s.sourceID == sourceID then
                found = true
                break
            end
        end
        if not found then
            sources[#sources + 1] = { sourceType = sourceType, sourceID = sourceID }
        end
    end
    
    do
        local db = ns.CollectibleSourceDB
        if db then
            for npcID, npcData in pairs(db.npcs or {}) do
                for i = 1, #npcData do RegisterDrop(npcData[i], "npc", npcID) end
            end
            for objID, objData in pairs(db.objects or {}) do
                for i = 1, #objData do RegisterDrop(objData[i], "object", objID) end
            end
            for zoneID, zoneData in pairs(db.fishing or {}) do
                for i = 1, #zoneData do RegisterDrop(zoneData[i], "fishing", zoneID) end
            end
            for containerID, cData in pairs(db.containers or {}) do
                local drops = cData.drops or cData
                if type(drops) == "table" then
                    for i = 1, #drops do RegisterDrop(drops[i], "container", containerID) end
                end
            end
        end
    end
    
    -- Persistent state
    if not ns._trackDBSelected then ns._trackDBSelected = {} end
    
    -- Detail card (subtle background panel for selected item info)
    local detailCard = ns.UI.Factory:CreateContainer(trackSection.content, trackContentWidth, 80, true)
    if detailCard and ApplySettingsChrome then
        ApplySettingsChrome(detailCard, SettingsNestedCardBg(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.5 })
    end
    
    -- Detail card children (created once, updated on selection)
    local detailNameText = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    detailNameText:SetPoint("TOPLEFT", 10, -8)
    detailNameText:SetPoint("RIGHT", detailCard, "RIGHT", -10, 0)
    detailNameText:SetJustifyH("LEFT")
    detailNameText:SetWordWrap(true)
    
    local detailInfoText = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    detailInfoText:SetPoint("TOPLEFT", 10, -26)
    detailInfoText:SetPoint("RIGHT", detailCard, "RIGHT", -10, 0)
    detailInfoText:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(detailInfoText, "Muted")
    detailInfoText:SetWordWrap(true)
    
    -- Tracked checkbox (inside detail card)
    local trackedCheckbox = CreateThemedCheckbox(detailCard)
    trackedCheckbox:SetPoint("TOPLEFT", 8, -48)
    
    local trackedLabel = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    trackedLabel:SetPoint("LEFT", trackedCheckbox, "RIGHT", 6, 0)
    trackedLabel:SetText((ns.L and ns.L["TRACKED"]) or "Tracked")
    ns.UI_SetTextColorRole(trackedLabel, "Bright")
    
    -- Repeatable checkbox (inside detail card, right of Tracked)
    local repeatableCheckbox = CreateThemedCheckbox(detailCard)
    repeatableCheckbox:SetPoint("LEFT", trackedLabel, "RIGHT", 20, 0)
    
    local repeatableLabel = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    repeatableLabel:SetPoint("LEFT", repeatableCheckbox, "RIGHT", 6, 0)
    repeatableLabel:SetText((ns.L and ns.L["REPEATABLE_LABEL"]) or "Repeatable")
    ns.UI_SetTextColorRole(repeatableLabel, "Bright")
    
    -- Placeholder when nothing is selected
    local detailPlaceholder = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    detailPlaceholder:SetPoint("TOPLEFT", 10, -8)
    detailPlaceholder:SetPoint("RIGHT", detailCard, "RIGHT", -10, 0)
    detailPlaceholder:SetText("|cff555555" .. ((ns.L and ns.L["SELECT_ITEM_HINT"]) or "Select an item above to view details.") .. "|r")
    detailPlaceholder:SetJustifyH("LEFT")
    
    trackedCheckbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if self.checkTexture then self.checkTexture:SetShown(isChecked) end
        local sel = ns._trackDBSelected
        if not sel or not sel.key then return end
        local info = itemRegistry[sel.key]
        if not info then return end
        local srcList = info.sources
        for si = 1, #srcList do
            local src = srcList[si]
            WarbandNexus:SetBuiltinTracked(src.sourceType, src.sourceID, info.itemID, isChecked)
        end
        local statusStr = isChecked
            and ("|cff00ff00" .. ((ns.L and ns.L["TRACKED"]) or "Tracked") .. "|r")
            or ("|cffff6600" .. ((ns.L and ns.L["UNTRACKED"]) or "Untracked") .. "|r")
        WarbandNexus:Print(format("|cff9370DB[WN]|r %s → %s", info.name, statusStr))
    end)
    
    repeatableCheckbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if self.checkTexture then self.checkTexture:SetShown(isChecked) end
        local sel = ns._trackDBSelected
        if not sel or not sel.key then return end
        local info = itemRegistry[sel.key]
        if not info then return end
        WarbandNexus:SetBuiltinRepeatable(info.type, info.itemID, isChecked)
        -- Update the info line to reflect the change
        info.repeatable = isChecked
        local repeatStr = isChecked
            and ("|cff00ff00" .. ((ns.L and ns.L["YES"]) or "Yes") .. "|r")
            or ("|cff666666" .. ((ns.L and ns.L["NO"]) or "No") .. "|r")
        WarbandNexus:Print(format("|cff9370DB[WN]|r %s → Repeatable: %s", info.name, repeatStr))
    end)
    
    local function IsItemFullyTracked(info)
        if not info or not info.sources then return true end
        local srcList2 = info.sources
        for si = 1, #srcList2 do
            local src = srcList2[si]
            if not WarbandNexus:IsBuiltinTracked(src.sourceType, src.sourceID, info.itemID) then
                return false
            end
        end
        return true
    end
    
    local function UpdateDetailPanel(key)
        local info = itemRegistry[key]
        if not info then
            detailPlaceholder:Show()
            detailNameText:SetText("")
            detailInfoText:SetText("")
            trackedCheckbox:Hide()
            trackedLabel:Hide()
            repeatableCheckbox:Hide()
            repeatableLabel:Hide()
            return
        end
        ns._trackDBSelected = { key = key }
        detailPlaceholder:Hide()
        
        -- Name with type color
        local typeColor = "ffffff"
        if info.type == "mount" then typeColor = "00ccff"
        elseif info.type == "pet" then typeColor = "44ff44"
        elseif info.type == "toy" then typeColor = "ff8800"
        elseif info.type == "illusion" then typeColor = "cc66ff" end
        detailNameText:SetText("|cff" .. typeColor .. info.name .. "|r")
        
        -- Info line (type + source count only, repeatable is now a checkbox)
        local typeName = info.type:sub(1,1):upper() .. info.type:sub(2)
        local srcCount = #info.sources
        local srcLabel = srcCount == 1 and ((ns.L and ns.L["SOURCE_SINGULAR"]) or "source") or ((ns.L and ns.L["SOURCE_PLURAL"]) or "sources")
        detailInfoText:SetText(format("%s  |cff444444·|r  %d %s", typeName, srcCount, srcLabel))
        
        -- Tracked checkbox
        local isTracked = IsItemFullyTracked(info)
        trackedCheckbox:SetChecked(isTracked)
        if trackedCheckbox.checkTexture then trackedCheckbox.checkTexture:SetShown(isTracked) end
        trackedCheckbox:Show()
        trackedLabel:Show()
        
        -- Repeatable checkbox (check override first, then DB default)
        local override = WarbandNexus:GetRepeatableOverride(info.type, info.itemID)
        local isRepeatable = (override ~= nil) and override or info.repeatable
        repeatableCheckbox:SetChecked(isRepeatable)
        if repeatableCheckbox.checkTexture then repeatableCheckbox.checkTexture:SetShown(isRepeatable) end
        repeatableCheckbox:Show()
        repeatableLabel:Show()
    end
    
    -- Dropdown: Select item from DB
    trackYOffset = CreateDropdownWidget(trackSection.content, {
        name = (ns.L and ns.L["SELECT_ITEM"]) or "Select Item",
        desc = (ns.L and ns.L["SELECT_ITEM_DESC"]) or "Choose a collectible to manage.",
        values = function() return dropdownValues end,
        get = function()
            return ns._trackDBSelected and ns._trackDBSelected.key or nil
        end,
        set = function(_, val)
            UpdateDetailPanel(val)
        end,
    }, trackYOffset)
    
    -- Position detail card below dropdown (fixed height: always visible as card)
    local DETAIL_CARD_HEIGHT = 78
    detailCard:SetPoint("TOPLEFT", 0, trackYOffset)
    detailCard:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
    detailCard:SetHeight(DETAIL_CARD_HEIGHT)
    detailCard:Show()
    
    -- Restore previous selection or show placeholder
    if ns._trackDBSelected and ns._trackDBSelected.key and itemRegistry[ns._trackDBSelected.key] then
        UpdateDetailPanel(ns._trackDBSelected.key)
    else
        detailPlaceholder:Show()
        detailNameText:SetText("")
        detailInfoText:SetText("")
        trackedCheckbox:Hide()
        trackedLabel:Hide()
        repeatableCheckbox:Hide()
        repeatableLabel:Hide()
    end
    trackYOffset = trackYOffset - DETAIL_CARD_HEIGHT - 16
    
    -- SUB-PANEL: Custom Entries
    
    -- Divider line
    local trackDivider2
    if ns.UI.Factory and ns.UI.Factory.CreateThemeDivider then
        trackDivider2 = ns.UI.Factory:CreateThemeDivider(trackSection.content, {
            orientation = "horizontal",
            variant = "section",
            thickness = 2,
        })
        if trackDivider2 then
            trackDivider2:SetPoint("TOPLEFT", 0, trackYOffset)
            trackDivider2:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
        end
    end
    trackYOffset = trackYOffset - 12
    
    -- Sub-header
    local customSectionHeader = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    customSectionHeader:SetPoint("TOPLEFT", 0, trackYOffset)
    customSectionHeader:SetText("|cffffcc00" .. ((ns.L and ns.L["CUSTOM_ENTRIES"]) or "Custom Entries") .. "|r")
    trackYOffset = trackYOffset - 20
    
    -- Custom entries list (no separate "Current:" label — shown inline)
    local customListText = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    customListText:SetPoint("TOPLEFT", 4, trackYOffset)
    customListText:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
    customListText:SetJustifyH("LEFT")
    customListText:SetWordWrap(true)
    
    -- Custom entries list builder + remove dropdown value builder
    local removeDropdownValues = {}
    local function RefreshCustomList()
        if not WarbandNexus.db or not WarbandNexus.db.global then
            customListText:SetText("|cff555555" .. ((ns.L and ns.L["NO_CUSTOM_ENTRIES"]) or "No custom entries.") .. "|r")
            wipe(removeDropdownValues)
            return
        end
        local trackDB = WarbandNexus.db.global.trackDB
        if not trackDB or not trackDB.custom then
            customListText:SetText("|cff555555" .. ((ns.L and ns.L["NO_CUSTOM_ENTRIES"]) or "No custom entries.") .. "|r")
            wipe(removeDropdownValues)
            return
        end
        local lines = {}
        wipe(removeDropdownValues)
        for npcID, drops in pairs(trackDB.custom.npcs or {}) do
            for i = 1, #drops do
                local d = drops[i]
                local repStr = d.repeatable and " |cff44cc44(R)|r" or ""
                lines[#lines + 1] = format("|cff00ccff%s|r%s  |cff666666npc:%s|r",
                    d.name or "?", repStr, tostring(npcID))
                local removeKey = "npc:" .. tostring(npcID) .. ":" .. tostring(d.itemID or 0)
                removeDropdownValues[removeKey] = (d.name or "?") .. " (npc:" .. npcID .. ")"
            end
        end
        for objID, drops in pairs(trackDB.custom.objects or {}) do
            for i = 1, #drops do
                local d = drops[i]
                local repStr = d.repeatable and " |cff44cc44(R)|r" or ""
                lines[#lines + 1] = format("|cff00ccff%s|r%s  |cff666666obj:%s|r",
                    d.name or "?", repStr, tostring(objID))
                local removeKey = "object:" .. tostring(objID) .. ":" .. tostring(d.itemID or 0)
                removeDropdownValues[removeKey] = (d.name or "?") .. " (obj:" .. objID .. ")"
            end
        end
        if #lines == 0 then
            customListText:SetText("|cff555555" .. ((ns.L and ns.L["NO_CUSTOM_ENTRIES"]) or "No custom entries.") .. "|r")
        else
            customListText:SetText(table.concat(lines, "\n"))
        end
    end
    RefreshCustomList()
    -- Use a safe minimum height for the custom list (at least 14px per line, min 14px)
    local customListH = customListText:GetStringHeight()
    if not customListH or customListH < 14 then customListH = 14 end
    trackYOffset = trackYOffset - customListH - 12
    
    -- Form state
    if not ns._trackDBForm then ns._trackDBForm = {} end
    
    -- Item ID label
    local itemIDLabel = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    itemIDLabel:SetPoint("TOPLEFT", 0, trackYOffset)
    itemIDLabel:SetText((ns.L and ns.L["ITEM_ID_INPUT"]) or "Item ID")
    ns.UI_SetTextColorRole(itemIDLabel, "Bright")
    itemIDLabel:SetScript("OnEnter", function(self)
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["ITEM_ID_INPUT_DESC"]) or "Enter the item ID to track.")
    end)
    itemIDLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    trackYOffset = trackYOffset - 22
    
    -- Item ID editbox + Lookup button on the SAME row
    local editBoxWidth = math.floor(trackContentWidth * 0.45)
    local lookupBtnWidth = 100
    local inlineGap = 8
    
    local itemIDBox = ns.UI.Factory:CreateEditBox(trackSection.content)
    if itemIDBox then
        itemIDBox:SetHeight(30)
        itemIDBox:SetWidth(editBoxWidth)
        itemIDBox:SetPoint("TOPLEFT", 0, trackYOffset)
        itemIDBox:SetTextInsets(10, 10, 0, 0)
        itemIDBox:SetMaxLetters(20)
        itemIDBox:SetNumeric(false)
        if ApplySettingsChrome then
            ApplySettingsAccentChromeIdle(itemIDBox)
        end
        WireSettingsAccentButtonHover(itemIDBox)
        RegisterSettingsAccentChrome(itemIDBox)
        itemIDBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        itemIDBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    
    -- Lookup result text (positioned below the input row)
    local lookupResultText = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    lookupResultText:SetPoint("TOPLEFT", 0, trackYOffset - 34)
    lookupResultText:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
    lookupResultText:SetText("")
    lookupResultText:SetWordWrap(true)
    lookupResultText:SetJustifyH("LEFT")
    
    -- Lookup button (inline, right of editbox)
    local lookupBtn = ns.UI.Factory:CreateButton(trackSection.content)
    lookupBtn:SetSize(lookupBtnWidth, SETTINGS_COMPACT_BTN_H)
    lookupBtn:SetPoint("LEFT", itemIDBox, "RIGHT", inlineGap, 0)
    local lookupBtnColor = { 0.20, 0.50, 0.70 }
    if ApplySettingsChrome then
        ApplySettingsChrome(lookupBtn, SettingsControlChrome(), {lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3], 0.8})
    end
    local lookupBtnText = FontManager:CreateFontString(lookupBtn, "body", "OVERLAY")
    lookupBtnText:SetPoint("CENTER")
    lookupBtnText:SetText((ns.L and ns.L["LOOKUP_ITEM"]) or "Lookup")
    lookupBtnText:SetTextColor(lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3])
    lookupBtn:SetScript("OnClick", function()
        local rawID = itemIDBox:GetText()
        if rawID and issecretvalue and issecretvalue(rawID) then return end
        local itemID = tonumber(rawID)
        if not itemID then return end
        ns._trackDBForm.itemID = itemID
        ns._trackDBForm.itemName = nil
        ns._trackDBForm.itemIcon = nil
        ns._trackDBForm.itemType = nil
        WarbandNexus:LookupItem(itemID, function(_, name, icon, cType)
            if name then
                ns._trackDBForm.itemName = name
                ns._trackDBForm.itemIcon = icon
                ns._trackDBForm.itemType = cType
                local iconStr = icon and ("|T" .. icon .. ":16|t ") or ""
                lookupResultText:SetText(iconStr .. "|cff00ff00" .. name .. "|r |cff888888(" .. (cType or "item") .. ")|r")
            else
                lookupResultText:SetText("|cffff4444" .. ((ns.L and ns.L["ITEM_LOOKUP_FAILED"]) or "Item not found.") .. "|r")
            end
        end)
    end)
    lookupBtn:SetScript("OnEnter", function(self)
        if ApplySettingsChrome then
            ApplySettingsChrome(lookupBtn, SettingsControlChromeHover(), {lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3], 1})
        end
        ns.UI_SetTextColorRole(lookupBtnText, "Bright")
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["LOOKUP_ITEM_DESC"]) or "Resolve item name and type from ID.")
    end)
    lookupBtn:SetScript("OnLeave", function()
        if ApplySettingsChrome then
            ApplySettingsChrome(lookupBtn, SettingsControlChrome(), {lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3], 0.8})
        end
        lookupBtnText:SetTextColor(lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3])
        GameTooltip:Hide()
    end)
    
    -- Advance past: editbox (30) + lookup result line (18) + gap (12)
    trackYOffset = trackYOffset - 30 - 18 - 12
    
    -- Source Type dropdown
    trackYOffset = CreateDropdownWidget(trackSection.content, {
        name = (ns.L and ns.L["SOURCE_TYPE"]) or "Source Type",
        desc = (ns.L and ns.L["SOURCE_TYPE_DESC"]) or "NPC or Object.",
        values = { npc = (ns.L and ns.L["SOURCE_TYPE_NPC"]) or "NPC", object = (ns.L and ns.L["SOURCE_TYPE_OBJECT"]) or "Object" },
        get = function() return ns._trackDBForm.sourceType or "npc" end,
        set = function(_, val) ns._trackDBForm.sourceType = val end,
    }, trackYOffset)
    
    -- Source ID input
    local sourceIDBox
    trackYOffset, sourceIDBox = CreateInputWidget(trackSection.content, {
        name = (ns.L and ns.L["SOURCE_ID"]) or "Source ID",
        desc = (ns.L and ns.L["SOURCE_ID_DESC"]) or "NPC ID or Object ID.",
        width = trackContentWidth * 0.45,
        numeric = true,
    }, trackYOffset)
    
    -- Repeatable checkbox
    trackYOffset = CreateCheckboxGrid(trackSection.content, {
        {
            key = "trackDB_repeatable",
            label = (ns.L and ns.L["REPEATABLE_TOGGLE"]) or "Repeatable",
            tooltip = (ns.L and ns.L["REPEATABLE_TOGGLE_DESC"]) or "Whether this drop can be attempted multiple times per lockout.",
            get = function() return ns._trackDBForm.repeatable or false end,
            set = function(val) ns._trackDBForm.repeatable = val end,
        },
    }, trackYOffset, trackContentWidth)
    
    -- [+ Add Entry] + [- Remove Selected] side-by-side
    if not ns._trackDBRemoveKey then ns._trackDBRemoveKey = nil end
    trackYOffset = CreateButtonGrid(trackSection.content, {
        {
            label = (ns.L and ns.L["ADD_ENTRY"]) or "+ Add Entry",
            tooltip = (ns.L and ns.L["ADD_ENTRY_DESC"]) or "Add this custom drop entry.",
            func = function()
                local f = ns._trackDBForm
                local rawItem = itemIDBox:GetText()
                local rawSrc = sourceIDBox:GetText()
                if (rawItem and issecretvalue and issecretvalue(rawItem))
                    or (rawSrc and issecretvalue and issecretvalue(rawSrc)) then
                    return
                end
                local itemID = tonumber(rawItem)
                local sourceID = tonumber(rawSrc)
                if not itemID or not sourceID then
                    WarbandNexus:Print("|cffff4444" .. ((ns.L and ns.L["ENTRY_ADD_FAILED"]) or "Item ID and Source ID are required.") .. "|r")
                    return
                end
                local drop = {
                    type = f.itemType or "item",
                    itemID = itemID,
                    name = f.itemName or ("Item " .. itemID),
                    repeatable = f.repeatable or nil,
                }
                local ok = WarbandNexus:AddCustomDrop(f.sourceType or "npc", sourceID, drop, nil)
                if ok then
                    WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["ENTRY_ADDED"]) or "Custom entry added.") .. "|r")
                    ns._trackDBForm = {}
                    itemIDBox:SetText("")
                    sourceIDBox:SetText("")
                    lookupResultText:SetText("")
                    RefreshCustomList()
                else
                    WarbandNexus:Print("|cffff4444" .. ((ns.L and ns.L["ENTRY_ADD_FAILED"]) or "Failed to add entry.") .. "|r")
                end
            end,
            color = { 0.20, 0.60, 0.40 },
        },
        {
            label = (ns.L and ns.L["REMOVE_BUTTON"]) or "- Remove Selected",
            tooltip = (ns.L and ns.L["REMOVE_BUTTON_DESC"]) or "Remove the selected custom entry.",
            func = function()
                local val = ns._trackDBRemoveKey
                if not val or val == "" then return end
                local sourceType, sourceID, itemID = strsplit(":", val)
                sourceID = tonumber(sourceID)
                itemID = tonumber(itemID)
                if sourceType and sourceID and itemID then
                    local ok = WarbandNexus:RemoveCustomDrop(sourceType, sourceID, itemID)
                    if ok then
                        WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["ENTRY_REMOVED"]) or "Entry removed.") .. "|r")
                        ns._trackDBRemoveKey = nil
                        RefreshCustomList()
                    end
                end
            end,
            color = { 0.60, 0.22, 0.22 },
        },
    }, trackYOffset, trackContentWidth, 160)
    
    -- Remove entry dropdown (select which custom entry to remove)
    trackYOffset = CreateDropdownWidget(trackSection.content, {
        name = (ns.L and ns.L["REMOVE_ENTRY"]) or "Remove Custom Entry",
        desc = (ns.L and ns.L["REMOVE_ENTRY_DESC"]) or "Select a custom entry to remove.",
        values = function() return removeDropdownValues end,
        get = function() return ns._trackDBRemoveKey end,
        set = function(_, val) ns._trackDBRemoveKey = val end,
    }, trackYOffset)
    
    -- Final section height (expanded)
    local trackContentHeight = SettingsMeasuredSectionContentHeight(trackYOffset)
    local trackExpandedHeight = trackContentHeight + CONTENT_PADDING_TOP + SETTINGS_CARD_OUTER_BOTTOM_PAD
    trackSection.content:SetHeight(trackContentHeight)
    
    -- Default collapsed: hide content, use collapsed height
    trackSection.content:Hide()
    trackSection:SetHeight(COLLAPSED_HEIGHT)
    
    local trackSectionYBase = yOffset  -- yOffset before track section
    yOffset = yOffset - COLLAPSED_HEIGHT - SETTINGS_SECTION_GAP  -- default collapsed offset
    
    -- ADVANCED
    
    local advSection = CreateSection(parent, nil, effectiveWidth)
    AnchorSectionTop(advSection, yOffset)
    
    -- Debug checkboxes: same 2-column row-major grid as other settings cards.
    -- Order fills [autoOptimize | debug] then [tryCounter | debugVerbose] so Verbose sits under Debug.
    local debugOptions = {
        {
            key = "autoOptimize",
            label = (ns.L and ns.L["CONFIG_AUTO_OPTIMIZE"]) or "Auto-Optimize Database",
            tooltip = (ns.L and ns.L["CONFIG_AUTO_OPTIMIZE_DESC"]) or "Automatically optimize the database on login to keep storage efficient.",
            get = function() return WarbandNexus.db.profile.autoOptimize ~= false end,
            set = function(value) WarbandNexus.db.profile.autoOptimize = value end,
        },
        {
            key = "debug",
            label = (ns.L and ns.L["DEBUG_MODE"]) or "Debug Logging",
            tooltip = (ns.L and ns.L["DEBUG_MODE_DESC"]) or "Output verbose debug messages to chat for troubleshooting",
            get = function() return WarbandNexus.db.profile.debugMode end,
            set = function(value)
                WarbandNexus.db.profile.debugMode = value
                if ns.Profiler and ns.Profiler.SyncWithDebugMode then
                    ns.Profiler:SyncWithDebugMode()
                end
                local mf = WarbandNexus.mainFrame
                if mf and mf.SyncMainHeaderDebugReloadLayout then
                    mf:SyncMainHeaderDebugReloadLayout()
                end
            end,
        },
        {
            key = "debugTryCounterLoot",
            label = (ns.L and ns.L["DEBUG_TRYCOUNTER_LOOT"]) or "Try Counter Loot Debug",
            tooltip = (ns.L and ns.L["DEBUG_TRYCOUNTER_LOOT_DESC"]) or "Log loot flow only (LOOT_OPENED, source resolution, zone fallback). Rep/currency cache logs are suppressed.",
            get = function() return WarbandNexus.db.profile.debugTryCounterLoot end,
            set = function(value) WarbandNexus.db.profile.debugTryCounterLoot = value end,
        },
        {
            key = "debugVerbose",
            parentKey = "debug",
            label = (ns.L and ns.L["CONFIG_DEBUG_VERBOSE"]) or "Debug Verbose (cache/scan/tooltip logs)",
            tooltip = (ns.L and ns.L["CONFIG_DEBUG_VERBOSE_DESC"]) or "When Debug Mode is on, also show currency/reputation cache, bag scan, tooltip and profession logs. Leave off to reduce chat spam.",
            get = function() return WarbandNexus.db.profile.debugVerbose end,
            set = function(value) WarbandNexus.db.profile.debugVerbose = value end,
        },
    }

    local advInnerW = GetSettingsSectionContentWidth(effectiveWidth)
    local advGridYOffset = CreateCheckboxGrid(advSection.content, debugOptions, 0, advInnerW)

    -- Calculate section height
    local advContentHeight = SettingsMeasuredSectionContentHeight(advGridYOffset)
    FinalizeSettingsSectionHeight(advSection, advContentHeight, false)
    
    -- Collapsible toggle handler for Track Item DB
    local function ToggleTrackSection()
        trackIsCollapsed = not trackIsCollapsed
        if trackIsCollapsed then
            trackSection.content:Hide()
            trackSection:SetHeight(COLLAPSED_HEIGHT)
            ns.UI_CollapseExpandSetState(trackChevronBtn, false)
        else
            trackSection.content:Show()
            trackSection:SetHeight(trackExpandedHeight)
            ns.UI_CollapseExpandSetState(trackChevronBtn, true)
        end
        -- Reposition Advanced section
        local advY = trackSectionYBase - trackSection:GetHeight() - SETTINGS_SECTION_GAP
        advSection:ClearAllPoints()
        AnchorSectionTop(advSection, advY)
        -- Recalculate total parent height
        local totalY = math.abs(advY) + advSection:GetHeight() + SETTINGS_SCROLL_INSET_BOTTOM
        parent:SetHeight(totalY)
    end
    collapseBtn:SetScript("OnClick", ToggleTrackSection)
    -- Make entire title text area clickable for convenience
    trackSection.titleText:SetScript("OnMouseUp", ToggleTrackSection)
    
    end -- advanced panel

    local contentH = math.abs(yOffset - (layoutOpts.startYOffset or 0))
    parent:SetHeight(math.max(80, contentH) + SETTINGS_SCROLL_INSET_BOTTOM)
end

-- MAIN WINDOW TAB (embedded in WarbandNexusFrame content scroll)

---Paint settings into the main window scroll host (replaces legacy floating panel).
---@param parent Frame
---@return number contentHeight
function WarbandNexus:DrawSettingsTab(parent)
    if not parent then return 0 end
    local mf = _G.WarbandNexusFrame
    local chrome = (mf and ns.UI_BeginTabChromeLayout) and ns.UI_BeginTabChromeLayout(mf) or nil
    local side = (chrome and chrome.side) or 12
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local navW = shell.SETTINGS_NAV_WIDTH or 148
    local navGap = shell.SETTINGS_NAV_GAP or 10
    local SUI = ns.SettingsUI
    local activePanel = (SUI and SUI.GetActivePanel and SUI.GetActivePanel()) or "general"
    local panelSubtitle = (SUI and SUI.PanelDescription and SUI.PanelDescription(activePanel))
        or (SUI and SUI.PanelLabel and SUI.PanelLabel(activePanel))
        or activePanel
    local tabTitle = (ns.L and ns.L["SETTINGS_TAB_TITLE"]) or "Settings"

    if chrome and chrome.headerParent and ns.UI_CreateStandardTabTitleCard then
        local C = COLORS
        local r, g, b = C.accent[1], C.accent[2], C.accent[3]
        local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
        local titleCard = select(1, ns.UI_CreateStandardTabTitleCard(chrome.headerParent, {
            tabKey = "settings",
            -- Plain title: white via the card's "Bright" text role (user wants white, not accent).
            titleText = tabTitle,
            subtitleText = panelSubtitle,
            showUnderline = false,
        }))
        if titleCard then
            if ns.UI_AnchorTabTitleCard then
                ns.UI_AnchorTabTitleCard(titleCard, chrome)
            end
            titleCard:Show()
            if ns.UI_AdvanceTabChromeYOffset then
                local headerBody = ns.UI_AdvanceTabChromeYOffset(chrome.yOffset, titleCard:GetHeight())
                if ns.UI_CommitTabFixedHeader then
                    ns.UI_CommitTabFixedHeader(mf, headerBody)
                end
            elseif mf and mf.fixedHeader then
                mf.fixedHeader:SetHeight((chrome.yOffset or 0) + (titleCard:GetHeight() or 64) + 8)
            end
            -- Settings header divider removed (user: no box/line under the settings header).
            if mf and mf._wnSettingsTitleRailSep and mf._wnSettingsTitleRailSep.Hide then
                mf._wnSettingsTitleRailSep:Hide()
            end
        end
    end

    local w = parent:GetWidth() or 640
    if w < 200 then w = 640 end
    local startY = -((ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8)

    local bodyRow = ns.UI.Factory:CreateContainer(parent, w, 1, false)
    if not bodyRow then
        BuildSettings(parent, w, { startYOffset = startY, sideInset = side, panel = activePanel })
        return parent:GetHeight() or 1
    end
    bodyRow:ClearAllPoints()
    bodyRow:SetPoint("TOPLEFT", parent, "TOPLEFT", side, startY)
    bodyRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -side, startY)

    local navCol = ns.UI.Factory:CreateContainer(bodyRow, navW, 1, false)
    local host = ns.UI.Factory:CreateContainer(bodyRow, 1, 1, false)
    if not navCol or not host then
        BuildSettings(parent, w, { startYOffset = startY, sideInset = 0, panel = activePanel })
        return parent:GetHeight() or 1
    end

    navCol:SetWidth(navW)
    navCol:SetPoint("TOPLEFT", bodyRow, "TOPLEFT", 0, 0)
    navCol:SetPoint("BOTTOMLEFT", bodyRow, "BOTTOMLEFT", 0, 0)

    local navBg = (ns.UI_GetNavRailSurfaceBackdrop and ns.UI_GetNavRailSurfaceBackdrop())
        or COLORS.surfaceViewport or COLORS.bg or { 0.04, 0.04, 0.05, 0.98 }
    local useClassicNav = ns.UI_IsClassicMode and ns.UI_IsClassicMode()
    if useClassicNav and ns.UI_ApplyClassicTransparentInterior then
        ns.UI_ApplyClassicTransparentInterior(navCol)
    elseif ns.UI_ApplyBorderlessSurface then
        ns.UI_ApplyBorderlessSurface(navCol, { navBg[1], navBg[2], navBg[3], 0.92 }, { surfaceTier = "surfaceViewport" })
    elseif ApplySettingsChrome then
        ApplySettingsChrome(navCol, { navBg[1], navBg[2], navBg[3], 0.92 }, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.35 })
        if ns.UI_HideFrameBorderQuartet then ns.UI_HideFrameBorderQuartet(navCol) end
    end
    -- Vertical rail divider removed (user: the orange rectangle next to the settings rail).
    -- Left nil so RefreshThemeChrome's `if navDivider then` guard skips re-showing it.
    local navDivider
    if navCol._wnSettingsNavDivider and navCol._wnSettingsNavDivider.Hide then
        navCol._wnSettingsNavDivider:Hide()
    end
    navCol._wnSettingsNavDivider = navDivider

    host:SetPoint("TOPLEFT", navCol, "TOPRIGHT", navGap, 0)
    host:SetPoint("TOPRIGHT", bodyRow, "TOPRIGHT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", bodyRow, "BOTTOMRIGHT", 0, 0)
    if useClassicNav then
        if ns.UI_ApplyClassicTransparentInterior then
            ns.UI_ApplyClassicTransparentInterior(bodyRow)
            ns.UI_ApplyClassicTransparentInterior(host)
        end
    end

    local navH = 0
    if SUI and SUI.BuildCategoryNav then
        navH = SUI.BuildCategoryNav(navCol, navW, activePanel, function(panelId)
            if mf and mf.currentTab == "settings" and WarbandNexus.PopulateContent then
                if mf.scroll then
                    mf.scroll:SetVerticalScroll(0)
                end
                WarbandNexus:PopulateContent()
            end
        end)
    end

    local hostW = math.max(240, (bodyRow:GetWidth() or w) - navW - navGap)
    BuildSettings(host, hostW, {
        startYOffset = -SETTINGS_LAYOUT.HOST_TOP_INSET,
        sideInset = SETTINGS_LAYOUT.HOST_SIDE_INSET,
        panel = activePanel,
        skipPanelIntro = true,
    })
    local hostH = host:GetHeight() or 0
    local rowH = math.max(navH, hostH, 120)
    bodyRow:SetHeight(rowH)
    host:SetHeight(rowH)
    navCol:SetHeight(rowH)

    if mf then
        mf._wnSettingsNavCol = navCol
        mf._wnSettingsBodyRow = bodyRow
        mf._wnSettingsHost = host
    end

    parent:SetHeight(math.abs(startY) + rowH + ((ns.UI_GetTabScrollContentBottomPad and ns.UI_GetTabScrollContentBottomPad()) or 12))
    return parent:GetHeight() or 1
end

function WarbandNexus:ShowSettings()
    if self.OpenOptions then
        self:OpenOptions()
    end
end

ns.ShowSettings = function() WarbandNexus:ShowSettings() end

-- After theme refresh (chains with VaultButton wrapper on ADDON_LOADED), re-apply settings control borders.
do
    if ns.UI_RefreshColors and not ns._wnSettingsUIAccentChromeHooked then
        ns._wnSettingsUIAccentChromeHooked = true
        local prevRefresh = ns.UI_RefreshColors
        ns.UI_RefreshColors = function(...)
            prevRefresh(...)
            RefreshSettingsAccentChrome()
        end
    end
end

-- CloseSpecialWindows path for ESC (legacy floating panel upgrades).
EnsureSettingsCloseSpecialHook()

-- Hide orphaned floating settings panel from pre-embed builds.
do
    local legacy = _G.WarbandNexusSettingsPanel
    if legacy and legacy.Hide then
        legacy:Hide()
    end
end
