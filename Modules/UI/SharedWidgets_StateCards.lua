--[[
    Warband Nexus - SharedWidgets StateCards (split from SharedWidgets.lua)
    Settings sections, card header layout, disabled module card, reset timer, DB badge, loading / error state cards.
    Loaded right after Modules/UI/SharedWidgets.lua (TOC) so every later file still finds these ns.UI_* exports.
]]

local _, ns = ...
assert(ns.UI and ns.UI_ApplyVisuals and ns.UI_CreateCard, "SharedWidgets_StateCards: load after SharedWidgets.lua")
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local issecretvalue = issecretvalue
local FontManager = ns.FontManager
local ThemeAPI = ns.UITheme.ThemeAPI
local COLORS = ns.UITheme.COLORS
local GetColors = ns.UITheme.GetColors
local UI_SPACING = ns.UI_SPACING
local IsClassicModeEnabled = ns.UI_IsClassicMode
local ApplyVisuals = ns.UI_ApplyVisuals
local ApplyStandardCardElevatedChrome = ns.UI_ApplyStandardCardElevatedChrome
local CreateCard = ns.UI_CreateCard

--- Semantic UI role → category (FontManager.FONT_ROLE / single theme source)
local function UIFontRole(roleKey)
    return FontManager:GetFontRole(roleKey)
end

-- SETTINGS UI HELPERS

--[[
    Create a bordered section/group container
    @param parent Frame - Parent frame
    @param title string - Section title (optional)
    @param width number - Section width
    @return Frame - Section container
]]
local function CreateSection(parent, title, width)
    local COLORS = GetColors()
    local sp = UI_SPACING
    local px = sp.SECTION_CARD_PADDING_X or 15
    local titleTop = sp.SECTION_CARD_TITLE_TOP or -12
    local bodyWithTitle = sp.SECTION_CARD_BODY_TOP_WITH_TITLE or -40
    local bodyNoTitle = sp.SECTION_CARD_BODY_TOP_NO_TITLE or -15
    
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetSize(width or 640, 1)  -- Height will be calculated
    
    local surf = COLORS.surfaceElevated or COLORS.bgLight
    if IsClassicModeEnabled() and ns.UI_ApplyClassicCardPanelChrome then
        ns.UI_ApplyClassicCardPanelChrome(section)
        section._wnSettingsSectionCard = true
    else
        ApplyVisuals(section, { surf[1], surf[2], surf[3], 0.35 }, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
        if ns.UI_ApplySectionChromeUnderlay then
            ns.UI_ApplySectionChromeUnderlay(section)
        end
    end
    
    -- Title (if provided) - inside card
    if title then
        local titleText = FontManager:CreateFontString(section, UIFontRole("settingsSectionTitle"), "OVERLAY", "accent")
        titleText:SetPoint("TOPLEFT", px, titleTop)
        titleText:SetText(title)
        if ns.UI_GetAccentTextRGBA then
            local ar, ag, ab, aa = ns.UI_GetAccentTextRGBA()
            if ns.UI_SetInkColor then
                ns.UI_SetInkColor(titleText, ar, ag, ab, aa)
            else
                titleText:SetTextColor(ar, ag, ab, aa)
            end
        end
        section.titleText = titleText
    end
    
    -- Content container (inset from border with proper padding)
    local content = CreateFrame("Frame", nil, section)
    local bodyTop = title and bodyWithTitle or bodyNoTitle
    content:SetPoint("TOPLEFT", px, bodyTop)
    content:SetPoint("TOPRIGHT", -px, bodyTop)
    section.content = content
    
    return section
end

--[[
    Create Card Header Layout with Icon and Text
    Standardized layout: Icon + Label + Value (all centered in card)
    @param parent Frame - Parent card frame
    @param iconTexture string - Icon texture path or atlas name
    @param iconSize number - Icon size in pixels
    @param isAtlas boolean - True if texture is atlas
    @param labelText string - Header label text
    @param valueText string - Value text (can be empty)
    @param labelFont string - Font category for label (default "subtitle")
    @param valueFont string - Font category for value (default "body")
    @return table - {icon, label, value, container}
]]
local function CreateCardHeaderLayout(parent, iconTexture, iconSize, isAtlas, labelText, valueText, labelFont, valueFont)
    labelFont = labelFont or FontManager:GetFontRole("cardHeaderLabel")
    valueFont = valueFont or FontManager:GetFontRole("cardHeaderValue")
    
    -- Create icon (centered vertically at left side)
    local iconFrame = ns.UI_CreateIcon(parent, iconTexture, iconSize, isAtlas, nil, true)
    iconFrame:SetPoint("CENTER", parent, "LEFT", 15 + (iconSize/2), 0)
    iconFrame:Show()
    
    -- Create container for text group
    local textContainer = CreateFrame("Frame", nil, parent)
    textContainer:SetHeight(40)
    textContainer:SetPoint("LEFT", iconFrame, "RIGHT", 12, 0)
    textContainer:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
    textContainer:SetPoint("CENTER", parent, "CENTER", 0, 0)
    
    -- Create label (centered in container)
    local label = FontManager:CreateFontString(textContainer, labelFont, "OVERLAY")
    label:SetText(labelText)
    ns.UI_SetTextColorRole(label, "Bright")
    label:SetJustifyH("LEFT")
    
    -- Create value (if provided)
    -- Texts are clamped to the container's RIGHT edge with wrapping off: long
    -- values (large gold amounts) used to grow past the container and overlap
    -- neighboring card content at intermediate widths.
    local value
    if valueText and valueText ~= "" then
        value = FontManager:CreateFontString(textContainer, valueFont, "OVERLAY")
        value:SetText(valueText)
        value:SetJustifyH("LEFT")
        value:SetWordWrap(false)
        if type(valueText) ~= "string" or (issecretvalue and issecretvalue(valueText))
            or not valueText:find("|cff", 1, true) then
            ns.UI_SetTextColorRole(value, "Normal")
        end

        -- Position texts centered in container
        label:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)  -- Label at center
        label:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        label:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
        value:SetPoint("TOP", textContainer, "CENTER", 0, -4)    -- Value below center
        value:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        value:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
    else
        -- Single text, center it
        label:SetPoint("CENTER", textContainer, "CENTER", 0, 0)
        label:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        label:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
    end
    label:SetWordWrap(false)
    
    return {
        icon = iconFrame,
        label = label,
        value = value,
        container = textContainer
    }
end

-- DISABLED MODULE STATE CARD

-- Creates a centered card showing module disabled state with Warband logo
-- @param parent: Parent frame to attach to
-- @param yOffset: Y offset from top
-- @param moduleName: Display name of the module (e.g., "Currency", "Reputation")
-- @return height: Total height consumed
local function CreateDisabledModuleCard(parent, yOffset, moduleName)
    local COLORS = ns.UI_COLORS
    local FontManager = ns.FontManager
    local SIDE_MARGIN = UI_SPACING.SIDE_MARGIN
    
    -- Calculate parent height dynamically
    local parentHeight = parent:GetHeight() or 600
    
    -- Create card frame that fills entire content area (full width and height)
    local card = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    card:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    card:SetPoint("BOTTOMRIGHT", -SIDE_MARGIN, SIDE_MARGIN)
    
    ApplyStandardCardElevatedChrome(card)
    local borderColor = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.72 }
    
    -- Content container (vertically centered)
    local contentContainer = CreateFrame("Frame", nil, card)
    contentContainer:SetSize(400, 200)
    contentContainer:SetPoint("CENTER", card, "CENTER", 0, 0)
    
    -- Icon container frame for proper layering
    local iconContainer = CreateFrame("Frame", nil, contentContainer)
    iconContainer:SetSize(80, 80)
    iconContainer:SetPoint("TOP", contentContainer, "TOP", 0, 0)
    
    -- Warband Logo (large, centered)
    local iconSize = 80
    local icon = iconContainer:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetAllPoints(iconContainer)
    icon:SetTexture(ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga")
    icon:SetTexCoord(0, 1, 0, 1)
    
    -- Icon border frame (thin 1px accent ring) - behind the icon
    local iconBorder = CreateFrame("Frame", nil, contentContainer, BackdropTemplateMixin and "BackdropTemplate")
    iconBorder:SetSize(iconSize + 4, iconSize + 4)
    iconBorder:SetPoint("CENTER", iconContainer, "CENTER", 0, 0)
    iconBorder:SetFrameLevel(iconContainer:GetFrameLevel() - 1)
    ApplyVisuals(iconBorder, nil, borderColor)  -- Just border, no background
    
    -- "Module Disabled" title
    local title = FontManager:CreateFontString(contentContainer, UIFontRole("moduleDisabledTitle"), "OVERLAY")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -24)
    title:SetText("|cffcccccc" .. ((ns.L and ns.L["MODULE_DISABLED"]) or "Module Disabled") .. "|r")
    
    -- Description with colored module name
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    local description = FontManager:CreateFontString(contentContainer, UIFontRole("moduleDisabledBody"), "OVERLAY")
    description:SetPoint("TOP", title, "BOTTOM", 0, -16)
    description:SetWidth(380)
    description:SetJustifyH("CENTER")
    local settingsStr = ThemeAPI.GetTextRoleHex("Bright") .. ((ns.L and ns.L["BTN_SETTINGS"]) or SETTINGS or "Settings") .. "|r"
    local moduleStr = "|cff" .. hexColor .. moduleName .. "|r"
    local mutedHex = ThemeAPI.GetTextRoleHex("Muted")
    description:SetText(
        mutedHex .. format((ns.L and ns.L["MODULE_DISABLED_DESC_FORMAT"]) or "Enable it in %s to use %s.", settingsStr, moduleStr) .. "|r"
    )
    
    card:Show()
    
    -- Return full height to parent
    return parentHeight - yOffset
end

-- RESET TIMER WIDGET

-- Creates a standardized reset timer with clock icon
-- @param parent: Parent frame to attach to
-- @param anchorPoint: Anchor point string (e.g., "RIGHT", "TOPRIGHT")
-- @param xOffset: X offset from anchor
-- @param yOffset: Y offset from anchor (default 0)
-- @param getSecondsFunc: Function that returns seconds until reset
-- @return table: { icon, text, container, Update }
local function CreateResetTimer(parent, anchorPoint, xOffset, yOffset, getSecondsFunc)
    local FontManager = ns.FontManager
    yOffset = yOffset or 0
    
    -- Container frame for icon + text (sized to fit content)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(150, 20)  -- Wider to accommodate icon + text
    container:SetPoint(anchorPoint, parent, anchorPoint, xOffset, yOffset)
    
    -- Reset text (positioned at RIGHT of container)
    local text = FontManager:CreateFontString(container, UIFontRole("resetTimerText"), "OVERLAY")
    text:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    local gr, gg, gb, ga = 0.3, 0.9, 0.3, 1
    if ns.UI_GetSemanticGreenColor then
        gr, gg, gb, ga = ns.UI_GetSemanticGreenColor()
    else
        local gc = COLORS.green or { gr, gg, gb, ga }
        gr, gg, gb, ga = gc[1], gc[2], gc[3], gc[4] or 1
    end
    text:SetTextColor(gr, gg, gb, ga)
    
    -- Clock icon (16x16) - positioned to the LEFT of text
    local icon = container:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    ns.UI_SetIcon(icon, "clock")
    icon:SetPoint("RIGHT", text, "LEFT", -4, 0)  -- 4px spacing from text
    
    -- Update function (uses shared Utilities:FormatTimeCompact)
    local function Update()
        if getSecondsFunc then
            local seconds = getSecondsFunc()
            text:SetText(((ns.L and ns.L["RESET_PREFIX"]) or "Reset:") .. " " .. ns.Utilities:FormatTimeCompact(seconds))
        end
    end
    
    -- Initial update
    Update()
    
    -- Auto-update every 60 seconds with a ticker (avoid per-frame polling).
    local function StartTicker()
        if container._resetTicker then return end
        container._resetTicker = C_Timer.NewTicker(60, Update)
    end

    container:SetScript("OnShow", StartTicker)
    container:SetScript("OnHide", function(self)
        if self._resetTicker then
            self._resetTicker:Cancel()
            self._resetTicker = nil
        end
    end)
    StartTicker()
    
    return {
        icon = icon,
        text = text,
        container = container,
        Update = Update
    }
end

-- Export reset timer helper
ns.UI_CreateResetTimer = CreateResetTimer

-- Export disabled state helper
ns.UI_CreateDisabledModuleCard = CreateDisabledModuleCard

-- Export Settings UI helpers
ns.UI_CreateSection = CreateSection

-- DB VERSION BADGE (Debug Logging)

---Creates a small badge showing which DB/cache is being used by this tab
---@return Frame Badge frame
local function CreateDBVersionBadge(parent, dataSource, anchorPoint, xOffset, yOffset)
    local FontManager = ns.FontManager
    anchorPoint = anchorPoint or "TOPRIGHT"
    xOffset = xOffset or -10
    yOffset = yOffset or -10
    
    -- Container frame
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(200, 20)
    badge:SetPoint(anchorPoint, parent, anchorPoint, xOffset, yOffset)
    badge:SetFrameStrata("HIGH")
    
    -- Badge text
    local text = FontManager:CreateFontString(badge, UIFontRole("versionBadge"), "OVERLAY")
    text:SetPoint("RIGHT", badge, "RIGHT", 0, 0)
    text:SetJustifyH("RIGHT")
    text:SetWidth(200)
    
    -- Color based on source type
    local color = "|cff999999" -- Gray for unknown
    if dataSource:find("Cache") then
        color = "|cff00ff00" -- Green for cache services (modern)
    elseif dataSource:find("LEGACY") or dataSource:find("db%.global") then
        color = "|cffffaa00" -- Orange for direct DB access (legacy)
    end
    
    text:SetText(color .. ((ns.L and ns.L["DB_LABEL"]) or "DB:") .. " " .. dataSource .. "|r")
    
    -- Tooltip on hover
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if ns.UI_GameTooltipAddRoleLine then
            ns.UI_GameTooltipAddRoleLine(GameTooltip, (ns.L and ns.L["DATA_SOURCE_TITLE"]) or "Data Source Information", "Bright")
        else
            GameTooltip:AddLine((ns.L and ns.L["DATA_SOURCE_TITLE"]) or "Data Source Information", 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((ns.L and ns.L["DATA_SOURCE_USING"]) or "This tab is using:", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(dataSource, 1, 1, 0)
        GameTooltip:AddLine(" ")
        
        if dataSource:find("Cache") then
            GameTooltip:AddLine(ns.UI_GetIconMarkup("status_ok", 12, 12, 0, 0) .. " " .. ((ns.L and ns.L["DATA_SOURCE_MODERN"]) or "Modern cache service (event-driven)"), 0, 1, 0)
        elseif dataSource:find("LEGACY") then
            GameTooltip:AddLine("|cffffaa00⚠|r " .. ((ns.L and ns.L["DATA_SOURCE_LEGACY"]) or "Legacy direct DB access"), 1, 0.67, 0)
            GameTooltip:AddLine((ns.L and ns.L["DATA_SOURCE_NEEDS_MIGRATION"]) or "Needs migration to cache service", 0.7, 0.7, 0.7)
        end
        
        -- Show current DB version
        local WarbandNexus = ns.WarbandNexus
        if WarbandNexus and WarbandNexus.db then
            local dbVersion = WarbandNexus.db.global.dataVersion or 1
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(((ns.L and ns.L["GLOBAL_DB_VERSION"]) or "Global DB Version:") .. " " .. dbVersion, 0.5, 0.5, 1)
        end
        
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return badge
end

-- Exports MUST live in this file: both functions are file-locals here. The structure
-- split moved these export lines into SharedWidgets_Factory.lua, where the names
-- resolved to nil globals — every tab using the badge/header layout errored on draw.
ns.UI_CreateCardHeaderLayout = CreateCardHeaderLayout
ns.UI_CreateDBVersionBadge = CreateDBVersionBadge

-- NOTE: CreateEditBox implementation moved to line 4816 (Factory pattern wrapper)
-- This duplicate implementation was removed to avoid confusion

-- LOADING STATE WIDGETS (Standardized Progress Indicator)

--- Looping spinner rotation via AnimationGroup (no per-frame Lua OnUpdate). Same pattern as the
--- login sync bar in UI.lua (`spinGroup` Rotation + SetLooping("REPEAT")).
--- Positive degrees = counter-clockwise, matching the previous SetRotation(+rad) OnUpdate (270 deg/s).
local SPINNER_DEGREES_PER_SEC = 270
local function AttachLoopingSpinnerRotation(host, tex)
    if not tex or not tex.CreateAnimationGroup then return nil end
    local ag = tex:CreateAnimationGroup()
    local rot = ag:CreateAnimation("Rotation")
    rot:SetDegrees(360)
    rot:SetDuration(360 / SPINNER_DEGREES_PER_SEC)
    ag:SetLooping("REPEAT")
    if host and host.HookScript then
        host:HookScript("OnShow", function()
            if not ag:IsPlaying() then ag:Play() end
        end)
    end
    ag:Play()
    return ag
end

local LOADING_CARD_H = 108
local LOADING_CARD_UPDATE_INTERVAL = 0.1 -- <= 10 Hz progress re-apply

local function ReadLoadingPercent(state)
    if not state then return 0 end
    local lp = state.loadingProgress
    local sp = state.scanProgress
    local v = lp or sp or 0
    if type(v) ~= "number" then return 0 end
    if v ~= v then return 0 end
    return math.min(100, math.max(0, math.floor(v + 0.5)))
end

--- Re-apply stage text / bar fill only when stage, percent or bar width changed.
local function ApplyLoadingCardProgress(card)
    local loadingState = card._wnLoadingState
    if not loadingState then return end
    local currentStage = loadingState.currentStage or ((ns.L and ns.L["PREPARING"]) or "Preparing")
    local progress = ReadLoadingPercent(loadingState)
    if currentStage ~= card._wnLastStage or progress ~= card._wnLastProgress then
        card._wnLastStage = currentStage
        card._wnLastProgress = progress
        card._wnProgressText:SetText(string.format("|cff888888%s - %d%%|r", currentStage, progress))
    end
    local bw = card._wnBarBg:GetWidth()
    if bw and bw > 0 then
        local fillW = math.max(1, bw * (progress / 100))
        if fillW ~= card._wnLastFillW then
            card._wnLastFillW = fillW
            card._wnBarFill:SetWidth(fillW)
        end
    end
end

local function LoadingCard_OnUpdate(card, elapsed)
    local loadingState = card._wnLoadingState
    if not loadingState or not loadingState.isLoading then
        card:SetScript("OnUpdate", nil)
        return
    end
    card._wnUpdateAccum = (card._wnUpdateAccum or 0) + (elapsed or 0)
    if card._wnUpdateAccum < LOADING_CARD_UPDATE_INTERVAL then return end
    card._wnUpdateAccum = 0
    ApplyLoadingCardProgress(card)
end

---Create standardized loading state card with animated spinner and progress bar
--- Cached per parent + title (`parent._wnLoadingStateCards`) and re-adopted on later calls.
---@return number newYOffset - New Y offset after card
local function UI_CreateLoadingStateCard(parent, yOffset, loadingState, title)
    if not loadingState or not loadingState.isLoading then
        return yOffset
    end
    
    local SIDE_MARGIN = UI_SPACING.SIDE_MARGIN
    local CARD_H = LOADING_CARD_H
    local titleStr = title or ((ns.L and ns.L["LOADING"]) or "Loading...")
    local cache = parent and parent._wnLoadingStateCards
    if parent and not cache then
        cache = {}
        parent._wnLoadingStateCards = cache
    end
    local loadingCard = cache and cache[titleStr]

    local BAR_W = 200
    if parent and parent.GetWidth then
        local pw = parent:GetWidth() or 0
        local w = pw - (SIDE_MARGIN * 2) - 20 - 40 - 15 - 20
        BAR_W = math.min(280, math.max(120, w))
    end

    if not loadingCard then
        loadingCard = CreateCard(parent, CARD_H)
        loadingCard._wnReadoptable = true   -- cached + re-adopted: never registry garbage (SectionPool)
        ApplyStandardCardElevatedChrome(loadingCard)
        
        -- Animated spinner (AnimationGroup rotation; replays on card OnShow).
        local spinnerFrame = ns.UI_CreateIcon(loadingCard, "auctionhouse-ui-loadingspinner", 40, true, nil, true)
        spinnerFrame:SetPoint("LEFT", 20, 0)
        spinnerFrame:Show()
        local spinner = spinnerFrame.texture
        loadingCard._wnSpinGroup = AttachLoopingSpinnerRotation(loadingCard, spinner)
        loadingCard:HookScript("OnHide", function()
            loadingCard:SetScript("OnUpdate", nil)
        end)
        
        -- Loading title
        local FontManager = ns.FontManager
        local loadingText = FontManager:CreateFontString(loadingCard, UIFontRole("loadingCardTitle"), "OVERLAY")
        loadingText:SetPoint("LEFT", spinner, "RIGHT", 15, 10)
        loadingText:SetText("|cff00ccff" .. titleStr .. "|r")
        loadingCard._wnTitleText = loadingText
        
        -- Progress indicator
        local progressText = FontManager:CreateFontString(loadingCard, UIFontRole("loadingCardProgress"), "OVERLAY")
        progressText:SetPoint("LEFT", spinner, "RIGHT", 15, -8)
        loadingCard._wnProgressText = progressText

        local barBg = loadingCard:CreateTexture(nil, "ARTWORK")
        barBg:SetSize(BAR_W, 5)
        barBg:SetPoint("TOPLEFT", progressText, "BOTTOMLEFT", 0, -6)
        local barTrack = COLORS.surfaceRowOdd or COLORS.bgLight or COLORS.bg
        barBg:SetColorTexture(barTrack[1], barTrack[2], barTrack[3], barTrack[4] or 1)
        loadingCard._wnBarBg = barBg
        local barFill = loadingCard:CreateTexture(nil, "OVERLAY")
        barFill:SetHeight(5)
        barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
        barFill:SetWidth(1)
        local acc = COLORS and COLORS.accent or {0.2, 0.6, 1}
        barFill:SetColorTexture(acc[1], acc[2], acc[3], 0.9)
        loadingCard._wnBarFill = barFill
        
        -- Hint text
        local hintText = FontManager:CreateFontString(loadingCard, UIFontRole("loadingCardHint"), "OVERLAY")
        hintText:SetPoint("TOPLEFT", barBg, "BOTTOMLEFT", 0, -6)
        hintText:SetPoint("RIGHT", loadingCard, "RIGHT", -16, 0)
        ns.UI_SetTextColorRole(hintText, "Muted")
        hintText:SetText((ns.L and ns.L["PLEASE_WAIT"]) or "Please wait...")

        if cache then cache[titleStr] = loadingCard end
    else
        -- Re-adopt: content teardown may have parked the card in the recycle bin.
        if loadingCard:GetParent() ~= parent then
            loadingCard:SetParent(parent)
        end
        loadingCard._wnBarBg:SetWidth(BAR_W)
    end

    loadingCard:ClearAllPoints()
    loadingCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    loadingCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)

    loadingCard._wnLoadingState = loadingState
    loadingCard._wnLastStage = nil
    loadingCard._wnLastProgress = nil
    loadingCard._wnLastFillW = nil
    loadingCard._wnUpdateAccum = 0
    ApplyLoadingCardProgress(loadingCard)
    loadingCard:SetScript("OnUpdate", LoadingCard_OnUpdate)
    
    loadingCard:Show()
    
    return yOffset + CARD_H + 8
end

---Create standardized error state card
---@return number newYOffset - New Y offset after card
local function UI_CreateErrorStateCard(parent, yOffset, errorMessage)
    if not errorMessage or errorMessage == "" then
        return yOffset
    end
    
    local SIDE_MARGIN = UI_SPACING.SIDE_MARGIN
    local errorCard = CreateCard(parent, 60)
    ApplyStandardCardElevatedChrome(errorCard)
    errorCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    errorCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Warning icon
    local warningIconFrame = ns.UI_CreateIcon(errorCard, ns.UI_GetIconAtlas("warning") or "services-icon-warning", 24, true, nil, true)
    warningIconFrame:SetPoint("LEFT", 20, 0)
    warningIconFrame:Show()
    
    -- Error message
    local FontManager = ns.FontManager
    local errorText = FontManager:CreateFontString(errorCard, UIFontRole("errorCardBody"), "OVERLAY")
    errorText:SetPoint("LEFT", warningIconFrame, "RIGHT", 10, 0)
    local warnR, warnG, warnB, warnA = ThemeAPI.GetSemanticGoldColor()
    errorText:SetTextColor(warnR, warnG, warnB, warnA)
    errorText:SetText(ns.UI_GetSemanticGoldHex() .. errorMessage .. "|r")
    
    errorCard:Show()
    
    return yOffset + 70
end

---Create inline loading spinner (for small widgets like gold display)
---@return Frame spinnerFrame - Spinner frame for cleanup
local function UI_CreateInlineLoadingSpinner(parent, anchorFrame, anchorPoint, xOffset, yOffset, size)
    size = size or 16
    
    local spinnerFrame = ns.UI_CreateIcon(parent, "auctionhouse-ui-loadingspinner", size, true, nil, true)
    spinnerFrame:SetPoint(anchorPoint, anchorFrame, anchorPoint, xOffset, yOffset)
    spinnerFrame:Show()
    
    -- Animate rotation (AnimationGroup; no per-frame OnUpdate)
    spinnerFrame._wnSpinGroup = AttachLoopingSpinnerRotation(spinnerFrame, spinnerFrame.texture)
    
    return spinnerFrame
end

--- Create a persistent loading state panel that fills its parent.
--- Reusable: call panel:ShowLoading(title, progress, stage) / panel:HideLoading().
--- Visual style matches UI_CreateLoadingStateCard for consistency.
---@return Frame panel - Panel with :ShowLoading() / :HideLoading()
local function UI_CreateLoadingStatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetAllPoints(parent)
    ApplyStandardCardElevatedChrome(panel)
    panel:SetFrameLevel(parent:GetFrameLevel() + 10)
    panel:Hide()

    -- Spinner (same atlas as transient card)
    local spinnerFrame = ns.UI_CreateIcon(panel, "auctionhouse-ui-loadingspinner", 40, true, nil, true)
    spinnerFrame:SetPoint("CENTER", 0, 20)
    spinnerFrame:Show()
    local spinnerTex = spinnerFrame.texture
    panel._spinnerTex = spinnerTex

    panel._wnSpinGroup = AttachLoopingSpinnerRotation(panel, spinnerTex)

    -- Title
    local FM = ns.FontManager
    local titleText = FM:CreateFontString(panel, FM:GetFontRole("loadingPanelTitle"), "OVERLAY")
    titleText:SetPoint("TOP", spinnerFrame, "BOTTOM", 0, -10)
    titleText:SetJustifyH("CENTER")
    panel._titleText = titleText

    -- Progress text (stage + %)
    local progressText = FM:CreateFontString(panel, FM:GetFontRole("loadingPanelProgress"), "OVERLAY")
    progressText:SetPoint("TOP", titleText, "BOTTOM", 0, -6)
    progressText:SetJustifyH("CENTER")
    ns.UI_SetTextColorRole(progressText, "Dim")
    panel._progressText = progressText

    -- Progress bar
    local BAR_W = 200
    local barBg = panel:CreateTexture(nil, "ARTWORK")
    barBg:SetSize(BAR_W, 4)
    barBg:SetPoint("TOP", progressText, "BOTTOM", 0, -8)
    local panelBarTrack = COLORS.surfaceRowOdd or COLORS.bgLight or COLORS.bg
    barBg:SetColorTexture(panelBarTrack[1], panelBarTrack[2], panelBarTrack[3], panelBarTrack[4] or 1)
    panel._barBg = barBg

    local barFill = panel:CreateTexture(nil, "OVERLAY")
    barFill:SetHeight(4)
    barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
    barFill:SetWidth(1)
    barFill:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
    panel._barFill = barFill

    function panel:ShowLoading(title, progress, stage)
        local t = title or ((ns.L and ns.L["LOADING"]) or "Loading...")
        self._titleText:SetText("|cff00ccff" .. t .. "|r")
        local pct = math.min(100, math.max(0, progress or 0))
        local s = stage or ""
        if s ~= "" then
            self._progressText:SetText(string.format("%s - %d%%", s, pct))
        else
            self._progressText:SetText(string.format("%d%%", pct))
        end
        local barWidth = self._barBg:GetWidth()
        if barWidth and barWidth > 0 then
            self._barFill:SetWidth(math.max(1, barWidth * (pct / 100)))
        end
        self:Show()
    end

    function panel:HideLoading()
        self:Hide()
    end

    return panel
end

-- Export to namespace
ns.UI_CreateLoadingStateCard = UI_CreateLoadingStateCard
ns.UI_CreateErrorStateCard = UI_CreateErrorStateCard
ns.UI_CreateInlineLoadingSpinner = UI_CreateInlineLoadingSpinner
ns.UI_CreateLoadingStatePanel = UI_CreateLoadingStatePanel

assert(ns.UI_CreateSection and ns.UI_CreateLoadingStateCard and ns.UI_CreateLoadingStatePanel, "SharedWidgets_StateCards: exports missing")
