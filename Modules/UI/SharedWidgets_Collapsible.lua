--[[
    Warband Nexus - SharedWidgets SharedWidgets_Collapsible (ops-029 slice)
    Loaded after Modules/UI/SharedWidgets.lua core exports.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local issecretvalue = issecretvalue

ns.UI = ns.UI or {}
ns.UI.Factory = ns.UI.Factory or {}

local COLORS = ns.UI_COLORS
local UI_SPACING = ns.UI_SPACING
local UI_LAYOUT = ns.UI_LAYOUT or UI_SPACING
local GetPixelScale = ns.GetPixelScale
local PixelSnap = ns.PixelSnap
local ApplyVisuals = ns.UI_ApplyVisuals
local ForwardMouseWheelToScrollAncestor = ns.UI_ForwardMouseWheelToScrollAncestor
local GetColors = function() return ns.UI_COLORS end
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

local function UIFontRole(roleKey)
    return FontManager:GetFontRole(roleKey)
end

local function IsLightTheme()
    return ns.UI_IsLightMode and ns.UI_IsLightMode()
end

--- Section preset chrome: gold/danger used dark-only fills; light mode uses surface ladder.
local function ResolveSectionPresetChrome(preset)
    local accent = COLORS.accent
    local br, bg, bb, ba = accent[1], accent[2], accent[3], 0.5
    local sr, sg, sb, sa = accent[1], accent[2], accent[3], 0.9
    local headerBg

    if preset == "gold" then
        local g = COLORS.gold or { 1, 0.82, 0.2, 1 }
        br, bg, bb = g[1], g[2], g[3]
        sr, sg, sb = g[1], g[2], g[3]
        if IsLightTheme() then
            local surf = COLORS.surfaceHeaderChrome or COLORS.bgLight or COLORS.bgCard
            headerBg = { surf[1], surf[2], surf[3], surf[4] or 0.99 }
            ba = 0.42
            sa = 0.88
        else
            local surf = COLORS.surfaceHeaderChrome or COLORS.bgLight or COLORS.bgCard or COLORS.bg
            headerBg = { surf[1], surf[2], surf[3], surf[4] or 0.97 }
        end
    elseif preset == "danger" then
        br, bg, bb = 0.8, 0.25, 0.25
        sr, sg, sb = 0.8, 0.25, 0.25
        if IsLightTheme() then
            local surf = COLORS.surfaceHeaderChrome or COLORS.bgLight or COLORS.bgCard
            headerBg = { surf[1], surf[2], surf[3], surf[4] or 0.99 }
            ba = 0.38
            sa = 0.82
        else
            local surf = COLORS.surfaceHeaderChrome or COLORS.bgLight or COLORS.bgCard or COLORS.bg
            headerBg = { surf[1], surf[2], surf[3], surf[4] or 0.97 }
        end
    elseif preset == "accent" then
        if ns.UI_GetSubTabActiveBackdropRGBA then
            local ar, ag, ab, aa = ns.UI_GetSubTabActiveBackdropRGBA(accent)
            headerBg = { ar, ag, ab, aa or 0.98 }
        else
            local surf = COLORS.surfaceHeaderChrome or COLORS.bgLight or COLORS.bg
            headerBg = { surf[1], surf[2], surf[3], surf[4] or 0.99 }
        end
        ba = IsLightTheme() and 0.82 or 0.65
        sa = IsLightTheme() and 0.98 or 0.92
    else
        local surf = COLORS.surfaceElevated or COLORS.bgLight or COLORS.bg
        if IsLightTheme() then
            surf = COLORS.surfaceHeaderChrome or surf
        end
        headerBg = { surf[1], surf[2], surf[3], IsLightTheme() and (surf[4] or 0.99) or 0.96 }
    end

    return headerBg, br, bg, bb, ba, sr, sg, sb, sa
end

local function UseClassicSectionChrome()
    return ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()
end

--- Classic list-header fill — neutral surface, not accent preset washes.
local function ResolveClassicSectionHeaderBg()
    local surf = COLORS.surfaceHeaderChrome or COLORS.bgLight or COLORS.bgCard or COLORS.bg
    return { surf[1], surf[2], surf[3], surf[4] or 1 }
end

local function ResolveSurfaceTierColor(tier)
    if ns.UI_ResolveSurfaceTierColor then
        return ns.UI_ResolveSurfaceTierColor(tier)
    end
    local C = COLORS or {}
    if tier == "rowEven" then
        return C.surfaceRowEven or (UI_SPACING and UI_SPACING.ROW_COLOR_EVEN) or { 0.112, 0.112, 0.138, 0.96 }
    elseif tier == "rowOdd" then
        return C.surfaceRowOdd or (UI_SPACING and UI_SPACING.ROW_COLOR_ODD) or { 0.090, 0.090, 0.112, 0.96 }
    end
    return C.bg or { 0.065, 0.065, 0.082, 0.98 }
end

local function BuildCollapsibleSectionOpts(config)
    if type(config) ~= "table" then return nil end

    local bodyGetter = config.bodyGetter or config.animatedContent or config.frame
    if type(bodyGetter) ~= "function" then
        local bodyFrame = bodyGetter
        bodyGetter = function() return bodyFrame end
    end
    if not bodyGetter then return nil end

    local minBodyHeight = config.minBodyHeight or 0.1
    local updateVisibleFn = config.updateVisibleFn
    local scheduleVisibleUpdate = config.scheduleVisibleUpdate ~= false
    local updateScheduled = false
    local function NotifyVisibleUpdate()
        if type(updateVisibleFn) ~= "function" then return end
        if not scheduleVisibleUpdate then
            updateVisibleFn()
            return
        end
        if updateScheduled then return end
        updateScheduled = true
        C_Timer.After(0, function()
            updateScheduled = false
            if type(updateVisibleFn) == "function" then
                updateVisibleFn()
            end
        end)
    end

    local persistFn = config.persistToggle or config.persistFn
    local onUpdateExtra = config.onUpdate
    local onCompleteExtra = config.onComplete
    local refreshFn = config.refreshFn
    local hideOnCollapse = config.hideOnCollapse == true
    local showOnExpand = config.showOnExpand == true
    local hideBodyBeforeCollapseAnimate = config.hideBodyBeforeCollapseAnimate == true

    return {
        animatedContent = bodyGetter,
        persistToggle = function(exp)
            if type(persistFn) == "function" then
                persistFn(exp)
            end
        end,
        applyToggleBeforeCollapseAnimate = config.applyToggleBeforeCollapseAnimate == true,
        deferOnToggleUntilComplete = config.deferOnToggleUntilComplete == true,
        hideBodyBeforeCollapseAnimate = hideBodyBeforeCollapseAnimate,
        minBodyHeight = minBodyHeight,
        sectionOnUpdate = function(drawH)
            if config.wrapFrame and config.headerHeight then
                config.wrapFrame:SetHeight(config.headerHeight + math.max(minBodyHeight, drawH or 0))
            end
            if type(onUpdateExtra) == "function" then
                onUpdateExtra(drawH)
            end
            NotifyVisibleUpdate()
        end,
        sectionOnComplete = function(exp)
            local body = bodyGetter()
            if body then
                if exp and showOnExpand then
                    body:Show()
                    body:SetAlpha(1)
                elseif not exp and hideOnCollapse then
                    body:Hide()
                    body:SetHeight(minBodyHeight)
                end
            end
            if type(onCompleteExtra) == "function" then
                onCompleteExtra(exp)
            end
            if type(refreshFn) == "function" then
                refreshFn(exp)
            end
            NotifyVisibleUpdate()
        end,
    }
end

local function CreateCollapsibleHeader(parent, text, key, isExpanded, onToggle, iconTexture, isAtlas, indentLevel, noCategoryIcon, visualOpts)
    visualOpts = (type(visualOpts) == "table") and visualOpts or nil
    -- Support for nested headers (indentLevel: 0 = root, 1 = child, etc.)
    indentLevel = indentLevel or 0
    local indent = indentLevel * UI_LAYOUT.BASE_INDENT
    
    -- Create new header (no pooling for headers - they're infrequent and context-specific)
    -- Use max(1,...) so layout never gets 0/negative width when parent not yet laid out
    local parentW = (parent and parent:GetWidth()) or 0
    local sectionH = (visualOpts and type(visualOpts.sectionHeaderHeight) == "number" and visualOpts.sectionHeaderHeight)
        or (UI_LAYOUT and UI_LAYOUT.SECTION_COLLAPSE_HEADER_HEIGHT)
        or 36
    local suppressSectionChrome = visualOpts and visualOpts.suppressSectionChrome == true
    local sideInset = (UI_SPACING and UI_SPACING.SIDE_MARGIN) or (UI_LAYOUT and UI_LAYOUT.SIDE_MARGIN) or 12
    local useFullParentWidth = visualOpts and visualOpts.useFullParentWidth == true
    local stackWidth = visualOpts and tonumber(visualOpts.sectionStackWidth)
    local useClassicPanel = UseClassicSectionChrome()
    local header
    if useClassicPanel and not suppressSectionChrome then
        header = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        header._wnBlizzardButton = true
        header._wnClassicCollapsibleHeader = true
        if header.SetText then
            header:SetText("")
        end
        if ns.UI_NormalizeBlizzardButtonChrome then
            ns.UI_NormalizeBlizzardButtonChrome(header)
        end
    else
        header = CreateFrame("Button", nil, parent)
    end
    local headerW
    if stackWidth and stackWidth > 0 then
        headerW = math.max(1, stackWidth - indent)
    elseif useFullParentWidth then
        headerW = math.max(1, parentW - indent)
    else
        headerW = math.max(1, parentW - (sideInset * 2) - indent)
    end
    header:SetSize(headerW, sectionH)
    header:EnableMouse(true)
    if header.RegisterForClicks then
        header:RegisterForClicks("LeftButtonUp")
    end

    local preset = visualOpts and visualOpts.sectionPreset
    local headerBg, br, bg, bb, ba, sr, sg, sb, sa = ResolveSectionPresetChrome(preset)
    local ly = UI_LAYOUT or UI_SPACING
    local stripeW = (ly and ly.SECTION_HEADER_STRIPE_WIDTH) or 3
    local stripeVInset = (ly and ly.SECTION_HEADER_STRIPE_V_INSET) or 4
    local chevLeft = (ly and ly.SECTION_HEADER_COLLAPSE_CHEVRON_LEFT) or 12
    local catIconGap = (ly and ly.SECTION_HEADER_CATEGORY_ICON_GAP) or 8
    local titleAfterIcon = (ly and ly.SECTION_HEADER_TITLE_AFTER_ICON) or 12
    if useClassicPanel then
        chevLeft = chevLeft + 2
        catIconGap = catIconGap + 2
    end

    if not suppressSectionChrome then
        if useClassicPanel then
            if not header._wnBlizzardButton then
                local classicBg = ResolveClassicSectionHeaderBg()
                if ns.UI_ApplyClassicListHeaderChrome then
                    ns.UI_ApplyClassicListHeaderChrome(header, classicBg)
                elseif ns.UI_ApplyClassicPaneBackdrop then
                    ns.UI_ApplyClassicPaneBackdrop(header, classicBg)
                elseif ns.UI_ApplyClassicThinBorderChrome then
                    ns.UI_ApplyClassicThinBorderChrome(header, classicBg)
                end
                header._wnSectionHeaderBaseBg = classicBg
            end
            header._wnSectionStripe = nil
            if header._wnSectionRowJoin then header._wnSectionRowJoin:Hide() end
        else
            ApplyVisuals(header, headerBg, { br, bg, bb, ba })

            local stripe = header:CreateTexture(nil, "ARTWORK", nil, 2)
            stripe:SetSize(stripeW, math.max(4, sectionH - stripeVInset - stripeVInset))
            stripe:SetPoint("LEFT", 4, 0)
            stripe:SetColorTexture(sr, sg, sb, sa)
            header._wnSectionStripe = stripe
            if ns.UI_RegisterAccentStripe then
                ns.UI_RegisterAccentStripe(stripe)
            end
            if header._wnHairlinebottom and header._wnHairlinebottom.Hide then
                header._wnHairlinebottom:Hide()
            end
            -- Soft join into first row (same accent; lower alpha than header border).
            if not header._wnSectionRowJoin then
                local join = header:CreateTexture(nil, "BORDER", nil, 1)
                join:SetHeight(1)
                join:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", stripeW + 8, 1)
                join:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 1)
                header._wnSectionRowJoin = join
            end
            header._wnSectionRowJoin:SetColorTexture(br, bg, bb, 0.28)
            header._wnSectionRowJoin:Show()
        end
    else
        header._wnSectionStripe = nil
        if header._wnSectionRowJoin then header._wnSectionRowJoin:Hide() end
    end
    
    -- Expand/collapse: shared Button + single texture (parent header handles click)
    local iconTint = COLORS.accent
    local chevSz = (ly and ly.SECTION_COLLAPSE_CHEVRON_SIZE) or (UI_SPACING and UI_SPACING.COLLAPSE_EXPAND_BUTTON_SIZE) or 22
    local expandIcon = ns.UI_CreateCollapseExpandControl(header, isExpanded, {
        enableMouse = false,
        size = chevSz,
        vertexColor = { iconTint[1] * 1.5, iconTint[2] * 1.5, iconTint[3] * 1.5, 1 },
    })
    expandIcon:SetPoint("LEFT", chevLeft + indent, 0)

    local textAnchor = expandIcon
    local textOffset = titleAfterIcon
    
    -- Category icon: skip when noCategoryIcon (e.g. PvE uses favorite star in that slot)
    if noCategoryIcon then
        iconTexture = nil
    elseif not iconTexture or iconTexture == "" then
        iconTexture = isAtlas and "icons_64x64_important" or "Interface\\Icons\\INV_Misc_Coin_01"
    end
    local categoryIcon = nil
    if iconTexture then
        categoryIcon = header:CreateTexture(nil, "ARTWORK")
        local iconSize = (UI_LAYOUT and UI_LAYOUT.HEADER_ICON_SIZE) or 24
        categoryIcon:SetSize(iconSize, iconSize)
        categoryIcon:SetPoint("LEFT", expandIcon, "RIGHT", catIconGap, 0)
        
        -- Use atlas only (isAtlas=true from Collections); texture path fallback for legacy callers
        if isAtlas then
            local ok = pcall(categoryIcon.SetAtlas, categoryIcon, iconTexture, false)
            if not ok then
                categoryIcon:SetAtlas("icons_64x64_important", false)
            end
            categoryIcon:Show()
        else
            -- iconTexture: string path veya number (fileID); WoW ikisini de kabul eder
            categoryIcon:SetTexture(iconTexture)
            if type(iconTexture) == "string" then
                categoryIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            categoryIcon:Show()
        end
        -- Anti-flicker optimization
        categoryIcon:SetSnapToPixelGrid(false)
        categoryIcon:SetTexelSnappingBias(0)
        
        textAnchor = categoryIcon
        textOffset = titleAfterIcon
    end
    
    -- Header text (title font — matches Characters tab section labels)
    local headerText = FontManager:CreateFontString(header, UIFontRole("sectionCollapsibleTitle"), "OVERLAY")
    headerText:SetPoint("LEFT", textAnchor, "RIGHT", textOffset, 0)
    headerText:SetJustifyH("LEFT")
    headerText:SetText(text)
    if preset == "danger" then
        ns.UI_SetTextColorRole(headerText, "Muted")
    else
        ns.UI_SetTextColorRole(headerText, "Bright")
    end
    header._wnCollHeaderText = headerText
    if suppressSectionChrome then
        headerText:SetText("")
        headerText:Hide()
    end
    
    -- Pooled rows (PvE / Storage) refresh visualOpts each paint; click must read latest callbacks.
    header._wnCollVisualOpts = visualOpts

    -- Click handler: optional animatedContent body resizes instantly; then onToggle / callbacks.
    header:SetScript("OnClick", function()
        isExpanded = not isExpanded
        ns.UI_CollapseExpandSetState(expandIcon, isExpanded)

        local vo = header._wnCollVisualOpts or visualOpts
        local persistToggleFn = vo and vo.persistToggle
        if persistToggleFn then
            persistToggleFn(isExpanded)
        end

        local animContent = vo and vo.animatedContent
        local deferToggleUntilComplete = vo and vo.deferOnToggleUntilComplete == true
        local sectionOnUpdate = vo and vo.sectionOnUpdate
        local sectionOnCompleteFn = vo and vo.sectionOnComplete
        local function callSectionOnComplete(expandedState)
            if type(sectionOnCompleteFn) == "function" then
                sectionOnCompleteFn(expandedState)
            end
        end
        if type(animContent) == "function" then animContent = animContent() end
        if animContent then
            local fullH = animContent._wnSectionFullH
            if not fullH or fullH <= 0 then
                fullH = animContent:GetHeight()
                if fullH and fullH > 0 then animContent._wnSectionFullH = fullH end
            end

            local toggleBeforeCollapse = vo and vo.applyToggleBeforeCollapseAnimate == true
            if not isExpanded then
                if toggleBeforeCollapse then
                    onToggle(isExpanded)
                end
                if vo and vo.hideBodyBeforeCollapseAnimate then
                    animContent:Hide()
                end
                local drawEnd = (vo and vo.minBodyHeight) or 0.1
                animContent:SetHeight(drawEnd)
                if sectionOnUpdate then sectionOnUpdate(drawEnd) end
                if not toggleBeforeCollapse then
                    onToggle(isExpanded)
                end
                callSectionOnComplete(isExpanded)
            else
                animContent:Show()
                animContent:SetAlpha(1)
                local target = animContent._wnSectionFullH or math.max(0.1, animContent:GetHeight() or 0.1)
                target = math.max(0.1, target)
                if deferToggleUntilComplete then
                    animContent:SetHeight(target)
                    if sectionOnUpdate then sectionOnUpdate(target) end
                    onToggle(isExpanded)
                    callSectionOnComplete(isExpanded)
                else
                    -- onToggle first so callers can populate _wnSectionFullH / row heights before we read target.
                    onToggle(isExpanded)
                    local fullH2 = animContent._wnSectionFullH
                    if not fullH2 or fullH2 <= 0 then
                        fullH2 = animContent:GetHeight()
                        if fullH2 and fullH2 > 0 then
                            animContent._wnSectionFullH = fullH2
                        end
                    end
                    target = math.max(0.1, fullH2 or math.max(0.1, animContent:GetHeight() or 0.1))
                    animContent:SetHeight(target)
                    if sectionOnUpdate then sectionOnUpdate(target) end
                    callSectionOnComplete(isExpanded)
                end
            end
        else
            onToggle(isExpanded)
        end
    end)
    
    -- Apply highlight effect (skip on UIPanelButtonTemplate — template owns hover art)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight and not header._wnBlizzardButton then
        ns.UI.Factory:ApplyHighlight(header)
    end

    header:EnableMouseWheel(true)
    header:SetScript("OnMouseWheel", function(self, d)
        ForwardMouseWheelToScrollAncestor(self, d)
    end)
    
    return header, expandIcon, categoryIcon, headerText
end

ns.UI_CreateCollapsibleHeader = CreateCollapsibleHeader
ns.UI_BuildCollapsibleSectionOpts = BuildCollapsibleSectionOpts

assert(ns.UI_CreateCollapsibleHeader and ns.UI_BuildCollapsibleSectionOpts, "SharedWidgets_Collapsible: exports missing")
