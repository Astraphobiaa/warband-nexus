--[[
    Warband Nexus - Settings UI
    Standardized grid-based settings with event-driven architecture
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
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
    local maxItemsPerRow = (#buttons > 0) and #buttons or 2
    local itemsPerRow = math.min(maxItemsPerRow, math.max(1, math.floor((containerWidth + GRID_SPACING) / (minWidth + GRID_SPACING))))
    itemsPerRow = math.max(1, itemsPerRow)
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
        local labelText = btnData.label or btnData.text or ""
        buttonText:SetText(labelText)
        buttonText:SetTextColor(btnColor[1], btnColor[2], btnColor[3])

        if isPreset then
            ApplyThemePresetButtonChrome({ button = button, text = buttonText, color = btnColor }, isSelected)
            presetRegistry[#presetRegistry + 1] = { button = button, text = buttonText, color = btnColor }
        end
        
        -- OnClick
        local clickFunc = btnData.func or btnData.onClick
        button:SetScript("OnClick", function()
            if clickFunc then
                clickFunc()
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
    local function UpdateLabel(val)
        local currentValue = val or (option.get and option.get()) or (option.min or 0)
        local displayValue = (option.valueFormat and option.valueFormat(currentValue)) or string.format("%.1f", currentValue)
        label:SetText(string.format("%s: %s%s|r", optionName, AccentInlineHex(), displayValue))
    end
    
    UpdateLabel()
    
    -- Slider (single source of truth: Factory:CreateThemedSlider)
    local sliderOpts = {
        min = option.min or 0,
        max = option.max or 1,
        step = option.step or 0.1,
        value = option.get and option.get() or nil,
        height = 20,
    }

    if option.applyOnRelease then
        sliderOpts.onLiveChange = function(value)
            UpdateLabel(value)
        end
        sliderOpts.onCommit = function(value)
            if option.set then
                option.set(nil, value)
                UpdateLabel(value)
            end
        end
    else
        sliderOpts.onChange = function(value)
            if option.set then
                option.set(nil, value)  -- AceConfig pattern: (info, value)
                UpdateLabel(value)
            end
        end
    end

    local slider = ns.UI.Factory:CreateThemedSlider(parent, sliderOpts)
    slider.UpdateLabel = UpdateLabel
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
    
    return yOffset - 65, slider
end

-- Track subtitle elements for theme refresh
local subtitleElements = {}
local sliderElements = {}
local themePresetButtons = {}
-- Font-scale warning / AA hint of the current build (assigned by SettingsUI_Appearance.lua).
local themeTextRefs = { warningText = nil, aaHintText = nil }

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
    if themeTextRefs.warningText and themeTextRefs.warningText:IsShown() then
        themeTextRefs.warningText:SetText(FormatFontScaleWarningText())
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
        themeTextRefs = themeTextRefs,
    }
end

---@param parent Frame
---@param containerWidth number|nil
---@param layoutOpts table|nil `{ startYOffset, sideInset }` for embedded main-window tab
local function BuildSettings(parent, containerWidth, layoutOpts)
    local H = ns.SettingsUI._H
    local wipe = H.wipe
    local ns = H.ns
    local SETTINGS_LAYOUT = H.SETTINGS_LAYOUT
    local SETTINGS_SECTION_GAP = H.SETTINGS_SECTION_GAP
    local SETTINGS_SCROLL_INSET_BOTTOM = H.SETTINGS_SCROLL_INSET_BOTTOM
    local GetSettingsSectionCardWidth = H.GetSettingsSectionCardWidth
    local GetSettingsSectionContentWidth = H.GetSettingsSectionContentWidth
    local GetHeaderToolbarGap = H.GetHeaderToolbarGap
    local AppendSettingsPanelIntro = H.AppendSettingsPanelIntro
    local AppendSettingsSubSectionHeader = H.AppendSettingsSubSectionHeader
    local StackSettingsSubPanel = H.StackSettingsSubPanel
    local CreateSection = H.CreateSection
    local CreateCheckboxGrid = H.CreateCheckboxGrid
    local FinalizeSettingsSectionHeight = H.FinalizeSettingsSectionHeight
    local SettingsMeasuredSectionContentHeight = H.SettingsMeasuredSectionContentHeight
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
    themeTextRefs.warningText = nil
    themeTextRefs.aaHintText = nil
    
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

    -- Panel bodies live in SettingsUI_<Panel>.lua; each reads this context and returns the next yOffset.
    local panelCtx = {
        parent = parent,
        effectiveWidth = effectiveWidth,
        sideInset = sideInset,
        yOffset = yOffset,
        skipPanelIntro = skipPanelIntro,
        AnchorSectionTop = AnchorSectionTop,
    }

    if Want("general") then
        panelCtx.yOffset = yOffset
        yOffset = ns.SettingsUI.AppendGeneralPanel(panelCtx)
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
        panelCtx.yOffset = yOffset
        yOffset = ns.SettingsUI.AppendAccessPanel(panelCtx)
    end -- access panel

    if Want("filters") then
        panelCtx.yOffset = yOffset
        yOffset = ns.SettingsUI.AppendFiltersPanel(panelCtx)
    end -- filters panel

    if Want("notifications") then
        panelCtx.yOffset = yOffset
        yOffset = ns.SettingsUI.AppendNotificationsPanel(panelCtx)
    end -- notifications panel

    if Want("appearance") then
        panelCtx.yOffset = yOffset
        yOffset = ns.SettingsUI.AppendAppearancePanel(panelCtx)
    end -- appearance panel

    if Want("advanced") then
        panelCtx.yOffset = yOffset
        yOffset = ns.SettingsUI.AppendAdvancedPanel(panelCtx)
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
    local navW = shell.SETTINGS_NAV_WIDTH or 160
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
            titleCard:Show()
            if ns.UI_PageStack_Place then
                local headerBody = ns.UI_PageStack_Place(chrome, titleCard)
                if ns.UI_CommitTabFixedHeader then
                    ns.UI_CommitTabFixedHeader(mf, headerBody)
                end
            elseif ns.UI_AdvanceTabChromeYOffset then
                if ns.UI_AnchorTabTitleCard then
                    ns.UI_AnchorTabTitleCard(titleCard, chrome)
                end
                local headerBody = ns.UI_AdvanceTabChromeYOffset(chrome.yOffset, titleCard:GetHeight())
                if ns.UI_CommitTabFixedHeader then
                    ns.UI_CommitTabFixedHeader(mf, headerBody)
                end
            elseif mf and mf.fixedHeader then
                if ns.UI_AnchorTabTitleCard then
                    ns.UI_AnchorTabTitleCard(titleCard, chrome)
                end
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
    if ns.UI_PageStack_AnchorBody then
        ns.UI_PageStack_AnchorBody(parent, bodyRow, -startY)
    else
        bodyRow:ClearAllPoints()
        bodyRow:SetPoint("TOPLEFT", parent, "TOPLEFT", side, startY)
        bodyRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -side, startY)
    end

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
