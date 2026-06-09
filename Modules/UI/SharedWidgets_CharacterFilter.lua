--[[
    Warband Nexus - Character tab sort/filter flyouts and section pick menus.
    Split from SharedWidgets.lua to reduce main chunk size (Lua 5.1 local limit).
    Loaded from WarbandNexus.toc immediately after Modules/UI/SharedWidgets.lua.
]]

local _, ns = ...
local UI_SPACING = ns.UI_SPACING or {}
local UI_LAYOUT = ns.UI_LAYOUT or UI_SPACING
--============================================================================
-- CHARACTER LIST SORT DROPDOWN (Reusable Icon Button)
--============================================================================

local activeSortDropdownMenu = nil
local activePickMenu = nil

local function CreateCharacterSortDropdown(parent, sortOptions, dbSortTable, onSortChanged)
    -- Symmetric Filter button: fixed size, icon + text centered as a group
    local buttonHeight = ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT or 32
    local btnWidth = 90
    local btn = ns.UI.Factory:CreateButton(parent, btnWidth, buttonHeight, false)

    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.6})
    end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("RIGHT", btn, "CENTER", -23, 0)  -- icon left of center; text centered
    icon:SetAtlas("uitools-icon-filter")
    icon:SetVertexColor(0.8, 0.8, 0.8)

    local text = btn:CreateFontString(nil, "OVERLAY")
    if ns.FontManager then
        ns.FontManager:ApplyFont(text, "body")
    else
        text:SetFontObject("GameFontNormal")
    end
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetText((ns.L and ns.L["FILTER_LABEL"]) or "Filter")
    text:SetTextColor(0.9, 0.9, 0.9)
    icon:SetPoint("RIGHT", text, "LEFT", -6, 0)

    btn:SetScript("OnEnter", function(self)
        icon:SetVertexColor(1, 1, 1)
        text:SetTextColor(1, 1, 1)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.15, 0.15, 0.15, 0.8}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.8})
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((ns.L and ns.L["SORT_BY_LABEL"]) or "Sort By:")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        icon:SetVertexColor(0.8, 0.8, 0.8)
        text:SetTextColor(0.9, 0.9, 0.9)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.12, 0.12, 0.15, 1}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.6})
        end
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function(self)
        if activeSortDropdownMenu and activeSortDropdownMenu:IsShown() then
            activeSortDropdownMenu:Hide()
            activeSortDropdownMenu = nil
            if self._sortClickCatcher then
                self._sortClickCatcher:Hide()
            end
            return
        end
        if activeSortDropdownMenu then
            activeSortDropdownMenu:Hide()
            activeSortDropdownMenu = nil
        end

        local itemCount = #sortOptions
        local itemHeight = (UI_SPACING and UI_SPACING.DROPDOWN_MENU_ROW_HEIGHT) or (UI_SPACING and UI_SPACING.ROW_HEIGHT) or 26
        local sideMargin = (UI_SPACING and UI_SPACING.SIDE_MARGIN) or 10
        local radioArea = 8 + 16 + 6  -- left pad + radio width + gap
        local minMenuWidth = math.max(btn:GetWidth(), 120)
        local maxLabelW = 0
        do
            local measure = self:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then ns.FontManager:ApplyFont(measure, "body") else measure:SetFontObject("GameFontNormal") end
            for j = 1, itemCount do
                local label = sortOptions[j].label or ""
                measure:SetText(label)
                local w = measure:GetStringWidth()
                if w and w > maxLabelW then maxLabelW = w end
            end
            measure:SetText("")
        end
        local menuWidth = math.max(minMenuWidth, math.ceil(maxLabelW) + sideMargin * 2 + radioArea + 16)

        local menu = ns.UI.Factory:CreateContainer(UIParent, menuWidth, 200, true)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        menu:SetClampedToScreen(true)
        menu:SetWidth(menuWidth)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(menu, {0.08, 0.08, 0.10, 0.98}, {ns.UI_COLORS.accent[1] * 0.6, ns.UI_COLORS.accent[2] * 0.6, ns.UI_COLORS.accent[3] * 0.6, 0.8})
        end
        activeSortDropdownMenu = menu

        local rawKey = dbSortTable and dbSortTable.key
        local currentKey = nil
        if type(rawKey) == "string" and rawKey ~= "" then
            for j = 1, itemCount do
                if sortOptions[j].key == rawKey then
                    currentKey = rawKey
                    break
                end
            end
        end
        if not currentKey and sortOptions[1] and sortOptions[1].key then
            currentKey = sortOptions[1].key
        end
        if not currentKey then
            currentKey = "manual"
        end

        local scrollChild = select(2, ns.UI_ApplyDropdownScrollLayout(menu, itemCount, itemHeight))
        local btnContentWidth = (scrollChild and scrollChild:GetWidth()) or (menuWidth - sideMargin * 2)
        local yPos = (UI_SPACING and UI_SPACING.DROPDOWN_INSET_TOP) or 4

        for i = 1, itemCount do
            local opt = sortOptions[i]
            local optionBtn = ns.UI.Factory:CreateButton(scrollChild or menu, btnContentWidth, itemHeight, true)
            optionBtn:SetPoint("TOPLEFT", sideMargin, -yPos)

            local isSelected = (currentKey == opt.key)
            local radio = (ns.UI_CreateThemedRadioButton and ns.UI_CreateThemedRadioButton(optionBtn, isSelected)) or nil
            local textX = 10
            if radio then
                radio:SetPoint("LEFT", 8, 0)
                if radio.innerDot then
                    radio.innerDot:SetShown(isSelected)
                end
                textX = 8 + 16 + 6  -- left of radio + radio width + gap
            end

            local optionText = optionBtn:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then
                ns.FontManager:ApplyFont(optionText, "body")
            else
                optionText:SetFontObject("GameFontNormal")
            end
            if radio then
                optionText:SetPoint("LEFT", radio, "RIGHT", 6, 0)
            else
                optionText:SetPoint("LEFT", textX, 0)
            end
            optionText:SetJustifyH("LEFT")
            optionText:SetText(opt.label)
            if isSelected then
                optionText:SetTextColor(ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3])
            else
                optionText:SetTextColor(1, 1, 1)
            end

            if ns.UI_ApplyVisuals then
                ns.UI_ApplyVisuals(optionBtn, {0.08, 0.08, 0.10, 0}, {0, 0, 0, 0})
            end
            if ns.UI.Factory.ApplyHighlight then
                ns.UI.Factory:ApplyHighlight(optionBtn)
            end

            optionBtn:SetScript("OnClick", function()
                dbSortTable.key = opt.key
                menu:Hide()
                activeSortDropdownMenu = nil
                if self._sortClickCatcher then
                    self._sortClickCatcher:Hide()
                end
                if onSortChanged then onSortChanged() end
            end)
            yPos = yPos + itemHeight
        end

        ns.UI_ApplyDropdownScrollLayout(menu, itemCount, itemHeight)

        menu:Show()

        local clickCatcher = btn._sortClickCatcher
        if not clickCatcher then
            clickCatcher = CreateFrame("Frame", nil, UIParent)
            clickCatcher:SetAllPoints()
            clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            clickCatcher:SetFrameLevel(menu:GetFrameLevel() - 1)
            clickCatcher:EnableMouse(true)
            clickCatcher:SetScript("OnMouseDown", function()
                if activeSortDropdownMenu then
                    activeSortDropdownMenu:Hide()
                    activeSortDropdownMenu = nil
                end
                clickCatcher:Hide()
            end)
            btn._sortClickCatcher = clickCatcher
        end
        clickCatcher:Show()

        local origHide = menu:GetScript("OnHide")
        menu:SetScript("OnHide", function(m)
            if clickCatcher then clickCatcher:Hide() end
            activeSortDropdownMenu = nil
            if origHide then origHide(m) end
        end)
    end)

    return btn
end

--============================================================================
-- CHARACTERS / PROFESSIONS: Filter + sort + section view (nested flyouts)
--============================================================================

---@param ownerBtn Button|nil
local function WnCloseFullAdvFilter(ownerBtn)
    if ownerBtn then
        if ownerBtn._wnAdvSub and ownerBtn._wnAdvSub.Hide then
            ownerBtn._wnAdvSub:Hide()
        end
        ownerBtn._wnAdvSub = nil
        if ownerBtn._wnAdvRoot and ownerBtn._wnAdvRoot.Hide then
            ownerBtn._wnAdvRoot:Hide()
        end
        ownerBtn._wnAdvRoot = nil
        if ownerBtn._sortClickCatcher then ownerBtn._sortClickCatcher:Hide() end
    end
    if activeSortDropdownMenu and activeSortDropdownMenu.Hide then
        activeSortDropdownMenu:Hide()
    end
    activeSortDropdownMenu = nil
end

--- Close Filter flyouts and row pick menus (resize / scroll / tab rebuild).
function ns.UI_CloseCharacterTabFlyoutMenus()
    WnCloseFullAdvFilter(nil)
    if activePickMenu and activePickMenu.Hide then
        activePickMenu:Hide()
    end
    activePickMenu = nil
end

--- Characters / Professions title card: sort modes + section filter + optional delete custom header.
--- opts: sortOptions, dbSortTable, dbSectionFilter, getCustomSections(), onRefresh(), onDeleteSection(groupId, groupName)
---@return Button|nil
local function CreateCharacterTabAdvancedFilterButton(parent, opts)
    if not parent or not opts or not ns.UI or not ns.UI.Factory or not ns.UI.Factory.CreateButton then
        return nil
    end
    local sortOptions = opts.sortOptions
    local dbSortTable = opts.dbSortTable
    local dbSectionFilter = opts.dbSectionFilter
    local getCustomSections = opts.getCustomSections
    local onRefresh = opts.onRefresh
    local onDeleteSection = opts.onDeleteSection
    if not sortOptions or not dbSortTable or not dbSectionFilter or not onRefresh then
        return nil
    end

    local buttonHeight = ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT or 32
    local btnWidth = 96
    local btn = ns.UI.Factory:CreateButton(parent, btnWidth, buttonHeight, false)
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.6})
    end
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetAtlas("uitools-icon-filter")
    icon:SetVertexColor(0.8, 0.8, 0.8)
    local text = btn:CreateFontString(nil, "OVERLAY")
    if ns.FontManager then ns.FontManager:ApplyFont(text, "body") else text:SetFontObject("GameFontNormal") end
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetText((ns.L and ns.L["FILTER_LABEL"]) or "Filter")
    text:SetTextColor(0.9, 0.9, 0.9)
    icon:SetPoint("RIGHT", text, "LEFT", -6, 0)

    local itemHeight = (UI_SPACING and UI_SPACING.DROPDOWN_MENU_ROW_HEIGHT) or (UI_SPACING and UI_SPACING.ROW_HEIGHT) or 26
    local sideMargin = (UI_SPACING and UI_SPACING.SIDE_MARGIN) or 10
    local radioArea = 8 + 16 + 6

    local function measureMaxLabelWidth(labels)
        local maxW = 0
        local measure = btn:CreateFontString(nil, "OVERLAY")
        if ns.FontManager then ns.FontManager:ApplyFont(measure, "body") else measure:SetFontObject("GameFontNormal") end
        for i = 1, #labels do
            measure:SetText(labels[i] or "")
            local w = measure:GetStringWidth()
            if w and w > maxW then maxW = w end
        end
        measure:SetText("")
        return maxW
    end

    local function openFlyoutFrom(anchorMenu, rows, anchorYOffset)
        if btn._wnAdvSub and btn._wnAdvSub.Hide then
            btn._wnAdvSub:Hide()
        end
        btn._wnAdvSub = nil
        if not rows or #rows == 0 then return end
        local labels = {}
        for i = 1, #rows do labels[i] = rows[i].label or "" end
        local mw = math.max(160, math.ceil(measureMaxLabelWidth(labels)) + sideMargin * 2 + radioArea + 16)
        local mh = #rows * itemHeight + ((UI_SPACING and UI_SPACING.AFTER_ELEMENT) or 8)
        local sub = ns.UI.Factory:CreateContainer(UIParent, mw, mh, true)
        sub:SetFrameStrata("FULLSCREEN_DIALOG")
        sub:SetFrameLevel((anchorMenu and anchorMenu:GetFrameLevel() or 300) + 5)
        sub:SetPoint("TOPLEFT", anchorMenu, "TOPRIGHT", 4, anchorYOffset or 0)
        sub:SetClampedToScreen(true)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(sub, {0.08, 0.08, 0.10, 0.98}, {ns.UI_COLORS.accent[1] * 0.55, ns.UI_COLORS.accent[2] * 0.55, ns.UI_COLORS.accent[3] * 0.55, 0.85})
        end
        btn._wnAdvSub = sub
        local bw = mw - sideMargin * 2
        for i = 1, #rows do
            local row = rows[i]
            local optionBtn = ns.UI.Factory:CreateButton(sub, bw, itemHeight, true)
            optionBtn:SetPoint("TOPLEFT", sideMargin, -(i - 1) * itemHeight - 4)
            local isSel = row.selected == true
            local radio = (ns.UI_CreateThemedRadioButton and ns.UI_CreateThemedRadioButton(optionBtn, isSel)) or nil
            local optionText = optionBtn:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then ns.FontManager:ApplyFont(optionText, "body") else optionText:SetFontObject("GameFontNormal") end
            if radio then
                radio:SetPoint("LEFT", 8, 0)
                if radio.innerDot then radio.innerDot:SetShown(isSel) end
                optionText:SetPoint("LEFT", radio, "RIGHT", 6, 0)
            else
                optionText:SetPoint("LEFT", 10, 0)
            end
            optionText:SetJustifyH("LEFT")
            optionText:SetText(row.label or "")
            if isSel then
                optionText:SetTextColor(ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3])
            else
                optionText:SetTextColor(1, 1, 1)
            end
            if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(optionBtn, {0.08, 0.08, 0.10, 0}, {0, 0, 0, 0}) end
            if ns.UI.Factory.ApplyHighlight then ns.UI.Factory:ApplyHighlight(optionBtn) end
            optionBtn:SetScript("OnClick", function()
                if row.onPick then row.onPick() end
                WnCloseFullAdvFilter(btn)
                onRefresh()
            end)
        end
        sub:Show()
        return sub
    end

    btn:SetScript("OnEnter", function(self)
        icon:SetVertexColor(1, 1, 1)
        text:SetTextColor(1, 1, 1)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.15, 0.15, 0.15, 0.8}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.8})
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((ns.L and ns.L["FILTER_MENU_TOOLTIP"]) or "Sort and filter which sections are visible.", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        icon:SetVertexColor(0.8, 0.8, 0.8)
        text:SetTextColor(0.9, 0.9, 0.9)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.12, 0.12, 0.15, 1}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.6})
        end
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function(self)
        if self._wnAdvRoot and self._wnAdvRoot:IsShown() then
            WnCloseFullAdvFilter(self)
            return
        end
        if activeSortDropdownMenu and activeSortDropdownMenu:IsShown() then
            activeSortDropdownMenu:Hide()
            activeSortDropdownMenu = nil
        end
        WnCloseFullAdvFilter(self)

        local L = ns.L
        local rootLabels = {
            (L and L["FILTER_SUBMENU_SORT"]) or "Sort…",
            (L and L["FILTER_SUBMENU_VIEW"]) or "Show section…",
        }
        local rw = math.max(btn:GetWidth(), math.ceil(measureMaxLabelWidth(rootLabels)) + sideMargin * 2 + 24)
        local rootRowCount = 2
        local rh = rootRowCount * itemHeight + ((UI_SPACING and UI_SPACING.AFTER_ELEMENT) or 8)
        local root = ns.UI.Factory:CreateContainer(UIParent, rw, rh, true)
        root._wnAdvRoot = true
        root:SetFrameStrata("FULLSCREEN_DIALOG")
        root:SetFrameLevel(300)
        root:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        root:SetClampedToScreen(true)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(root, {0.08, 0.08, 0.10, 0.98}, {ns.UI_COLORS.accent[1] * 0.6, ns.UI_COLORS.accent[2] * 0.6, ns.UI_COLORS.accent[3] * 0.6, 0.8})
        end
        activeSortDropdownMenu = root
        btn._wnAdvRoot = root

        local bw = rw - sideMargin * 2
        local function makeRootRow(index, label, onActivate)
            local rowBtn = ns.UI.Factory:CreateButton(root, bw, itemHeight, true)
            rowBtn:SetPoint("TOPLEFT", sideMargin, -(index - 1) * itemHeight - 4)
            if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(rowBtn, {0.08, 0.08, 0.10, 0}, {0, 0, 0, 0}) end
            if ns.UI.Factory.ApplyHighlight then ns.UI.Factory:ApplyHighlight(rowBtn) end
            local fs = rowBtn:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then ns.FontManager:ApplyFont(fs, "body") else fs:SetFontObject("GameFontNormal") end
            fs:SetPoint("LEFT", 10, 0)
            fs:SetJustifyH("LEFT")
            fs:SetTextColor(1, 1, 1)
            fs:SetText(label)
            rowBtn:SetScript("OnClick", function()
                onActivate(rowBtn)
            end)
            return rowBtn
        end

        makeRootRow(1, rootLabels[1], function()
            local rawKey = dbSortTable and dbSortTable.key
            local rows = {}
            for si = 1, #sortOptions do
                local opt = sortOptions[si]
                rows[#rows + 1] = {
                    label = opt.label,
                    selected = (rawKey == opt.key),
                    onPick = function()
                        dbSortTable.key = opt.key
                    end,
                }
            end
            openFlyoutFrom(root, rows, 0)
        end)

        makeRootRow(2, rootLabels[2], function()
            local cur = dbSectionFilter.sectionKey or "all"
            local rows = {
                {
                    label = (L and L["SECTION_FILTER_ALL"]) or "All sections",
                    selected = (cur == "all"),
                    onPick = function() dbSectionFilter.sectionKey = "all" end,
                },
                {
                    label = (L and L["SECTION_FILTER_FAVORITES"]) or "Favorites only",
                    selected = (cur == "favorites"),
                    onPick = function() dbSectionFilter.sectionKey = "favorites" end,
                },
                {
                    label = (L and L["SECTION_FILTER_REGULAR"]) or "Characters (ungrouped) only",
                    selected = (cur == "regular"),
                    onPick = function() dbSectionFilter.sectionKey = "regular" end,
                },
            }
            local customs = getCustomSections and getCustomSections() or {}
            for ci = 1, #customs do
                local g = customs[ci]
                local gid = g.id
                local lk = (ns.CharacterService and ns.CharacterService.GetCustomGroupListKey and ns.CharacterService:GetCustomGroupListKey(gid)) or ("group_" .. tostring(gid))
                local gname = g.name or gid
                rows[#rows + 1] = {
                    label = gname,
                    selected = (cur == lk),
                    onPick = function() dbSectionFilter.sectionKey = lk end,
                }
            end
            rows[#rows + 1] = {
                label = (L and L["SECTION_FILTER_UNTRACKED"]) or "Untracked only",
                selected = (cur == "untracked"),
                onPick = function() dbSectionFilter.sectionKey = "untracked" end,
            }
            openFlyoutFrom(root, rows, 0)
        end)

        root:Show()

        local clickCatcher = btn._sortClickCatcher
        if not clickCatcher then
            clickCatcher = CreateFrame("Frame", nil, UIParent)
            clickCatcher:SetAllPoints()
            clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            clickCatcher:SetFrameLevel((root:GetFrameLevel() or 300) - 2)
            clickCatcher:EnableMouse(true)
            clickCatcher:SetScript("OnMouseDown", function()
                WnCloseFullAdvFilter(btn)
            end)
            btn._sortClickCatcher = clickCatcher
        end
        clickCatcher:Show()

        local origHide = root:GetScript("OnHide")
        root:SetScript("OnHide", function(m)
            WnCloseFullAdvFilter(btn)
            if origHide then origHide(m) end
        end)
    end)

    return btn
end

--- Shared vertical pick menu (Factory rows). Row: { label, onPick?, noRadio?, selected?, isHeader? }
local function WnShowLabeledPickMenu(anchorFrame, rows, onDone)
    if not anchorFrame or type(rows) ~= "table" or #rows < 1 then return end
    local itemHeight = (UI_SPACING and UI_SPACING.DROPDOWN_MENU_ROW_HEIGHT) or 26
    local sideMargin = 10
    local labels = {}
    for i = 1, #rows do
        if rows[i].label then
            labels[#labels + 1] = rows[i].label
        end
    end
    if #labels < 1 then return end
    local mw = math.max(220, 40 + sideMargin * 2 + (function()
        local maxW = 0
        local measure = anchorFrame:CreateFontString(nil, "OVERLAY")
        if ns.FontManager then ns.FontManager:ApplyFont(measure, "body") else measure:SetFontObject("GameFontNormal") end
        for j = 1, #labels do
            measure:SetText(labels[j])
            local w = measure:GetStringWidth()
            if w and w > maxW then maxW = w end
        end
        measure:SetText("")
        return math.ceil(maxW)
    end)())
    local totalH = 8
    for i = 1, #rows do
        totalH = totalH + (rows[i].isHeader and (itemHeight - 6) or itemHeight)
    end
    if activePickMenu and activePickMenu.Hide then
        activePickMenu:Hide()
    end
    local catcher = CreateFrame("Frame", nil, UIParent)
    local menu = ns.UI.Factory:CreateContainer(UIParent, mw, totalH, true)
    activePickMenu = menu
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(320)
    menu:SetPoint("TOPLEFT", anchorFrame, "BOTTOMRIGHT", 4, -2)
    menu:SetClampedToScreen(true)
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(menu, {0.08, 0.08, 0.10, 0.98}, {ns.UI_COLORS.accent[1] * 0.55, ns.UI_COLORS.accent[2] * 0.55, ns.UI_COLORS.accent[3] * 0.55, 0.85})
    end
    local bw = mw - sideMargin * 2
    local y = 4
    for i = 1, #rows do
        local r = rows[i]
        if r.isHeader then
            local bar = CreateFrame("Frame", nil, menu)
            bar:SetSize(bw, itemHeight - 6)
            bar:SetPoint("TOPLEFT", sideMargin, -y)
            local fs = bar:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then ns.FontManager:ApplyFont(fs, "tabSubtitle") else fs:SetFontObject("GameFontNormalSmall") end
            fs:SetPoint("LEFT", 0, 0)
            fs:SetWidth(bw)
            fs:SetJustifyH("LEFT")
            fs:SetText(r.label or "")
            fs:SetTextColor(0.58, 0.62, 0.72)
            y = y + (itemHeight - 6)
        else
            local optionBtn = ns.UI.Factory:CreateButton(menu, bw, itemHeight, true)
            optionBtn:SetPoint("TOPLEFT", sideMargin, -y)
            local radio = nil
            if not r.noRadio then
                radio = (ns.UI_CreateThemedRadioButton and ns.UI_CreateThemedRadioButton(optionBtn, r.selected)) or nil
            end
            local optionText = optionBtn:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then ns.FontManager:ApplyFont(optionText, "body") else optionText:SetFontObject("GameFontNormal") end
            if radio then
                radio:SetPoint("LEFT", 8, 0)
                if radio.innerDot then radio.innerDot:SetShown(r.selected) end
                optionText:SetPoint("LEFT", radio, "RIGHT", 6, 0)
            else
                optionText:SetPoint("LEFT", 10, 0)
            end
            optionText:SetJustifyH("LEFT")
            optionText:SetText(r.label or "")
            if r.disabled then
                optionText:SetTextColor(0.45, 0.45, 0.48)
                optionBtn:EnableMouse(false)
            elseif r.selected then
                optionText:SetTextColor(ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3])
            else
                optionText:SetTextColor(1, 1, 1)
            end
            if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(optionBtn, {0.08, 0.08, 0.10, 0}, {0, 0, 0, 0}) end
            if ns.UI.Factory.ApplyHighlight and not r.disabled then ns.UI.Factory:ApplyHighlight(optionBtn) end
            if not r.disabled and r.onPick then
                optionBtn:SetScript("OnClick", function()
                    menu:Hide()
                    if catcher then catcher:Hide() end
                    r.onPick()
                    if onDone then onDone() end
                end)
            else
                optionBtn:SetScript("OnClick", nil)
            end
            y = y + itemHeight
        end
    end
    catcher:SetAllPoints()
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(menu:GetFrameLevel() - 1)
    catcher:EnableMouse(true)
    catcher:SetScript("OnMouseDown", function()
        menu:Hide()
        catcher:Hide()
    end)
    catcher:Show()
    menu:SetScript("OnHide", function()
        catcher:Hide()
        if activePickMenu == menu then
            activePickMenu = nil
        end
    end)
    menu:Show()
end

--- Popup: move character to / from a custom section (tracked non-favorites).
function ns.UI_ShowCharacterSectionAssignMenu(anchorFrame, charKey, profile, onDone)
    if not anchorFrame or not charKey or not profile or not ns.CharacterService then return end
    ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
    local L = ns.L
    local rows = {}
    local assignedGroupId = profile.characterGroupAssignments and profile.characterGroupAssignments[charKey]
    if assignedGroupId then
        rows[#rows + 1] = {
            label = (L and L["CUSTOM_HEADER_REMOVE_ASSIGN"]) or "Remove from custom header",
            selected = false,
            noRadio = true,
            onPick = function()
                ns.CharacterService:SetCharacterCustomSection(_G.WarbandNexus or ns.WarbandNexus, charKey, nil)
            end,
        }
    end
    local groups = profile.characterCustomGroups or {}
    for i = 1, #groups do
        local g = groups[i]
        rows[#rows + 1] = {
            label = g.name or g.id,
            selected = (profile.characterGroupAssignments[charKey] == g.id),
            onPick = function()
                ns.CharacterService:SetCharacterCustomSection(_G.WarbandNexus or ns.WarbandNexus, charKey, g.id)
            end,
        }
    end
    WnShowLabeledPickMenu(anchorFrame, rows, onDone)
end

--- Title-bar menu: new/delete custom headers + optional gold header highlight for one section (visual only).
function ns.UI_ShowCharacterSectionsToolbarMenu(anchorFrame, profile)
    if not anchorFrame or not profile or not ns.CharacterService then return end
    ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
    local L = ns.L
    local addon = _G.WarbandNexus or ns.WarbandNexus
    local rows = {}
    rows[#rows + 1] = { isHeader = true, label = (L and L["CUSTOM_HEADER_MENU_SECTION_HEADERS"]) or "Custom headers" }
    rows[#rows + 1] = {
        label = (L and L["CUSTOM_HEADER_MENU_NEW"]) or "New custom section…",
        noRadio = true,
        onPick = function()
            local function openNewHeaderDialog()
                local a = _G.WarbandNexus or ns.WarbandNexus
                if a and a.OpenCustomCharacterHeaderDialog then
                    a:OpenCustomCharacterHeaderDialog()
                end
            end
            -- Defer one tick so pick menu + click catcher finish hiding before the modal opens.
            if C_Timer and C_Timer.After then
                C_Timer.After(0, openNewHeaderDialog)
            else
                openNewHeaderDialog()
            end
        end,
    }
    local groups = profile.characterCustomGroups or {}
    if #groups == 0 then
        rows[#rows + 1] = {
            label = (L and L["CUSTOM_HEADER_MENU_NONE_YET"]) or "No sections yet - use New custom section above.",
            noRadio = true,
            disabled = true,
        }
    else
        rows[#rows + 1] = { isHeader = true, label = (L and L["CUSTOM_HEADER_MENU_DELETE_GROUP"]) or "Delete a section" }
        for i = 1, #groups do
            local g = groups[i]
            rows[#rows + 1] = {
                label = string.format((L and L["CUSTOM_HEADER_MENU_DELETE_FMT"]) or "Delete: %s", g.name or g.id),
                noRadio = true,
                onPick = function()
                    if addon and addon.ConfirmDeleteCustomCharacterHeader then
                        addon:ConfirmDeleteCustomCharacterHeader(g.id, g.name)
                    end
                end,
            }
        end
    end
    WnShowLabeledPickMenu(anchorFrame, rows, nil)
end

ns.UI_CreateCharacterSortDropdown = CreateCharacterSortDropdown
ns.UI_CreateCharacterTabAdvancedFilterButton = CreateCharacterTabAdvancedFilterButton