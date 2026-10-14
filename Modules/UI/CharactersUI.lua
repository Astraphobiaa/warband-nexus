--[[
    Warband Nexus - Characters Tab
    Display all tracked characters with gold, level, and last seen info

    WN_FACTORY: Gold/token text blocks and collapsible section hosts use `Factory:CreateContainer`; row chrome
    and delete icon buttons use `CreateButton`. Delete-confirm dialog prefers `UI_CreateThemedButton`, else
    Factory + ApplyVisuals; custom header dialogs fall back to plain `CreateFrame` only if Factory is absent.
    WN_PERF: Leaf rows virtualized (`VirtualListModule`); WoW Token request + lastSeen SavedVariables bumps throttled.

    SPLIT (TOC order, all after this file; satellites read the bind table at the end of this file):
      CharactersUI_GoldCards.lua    gold summary card geometry
      CharactersUI_Row.lua          DrawCharacterRow, row interior relayout, mail column
      CharactersUI_ColumnHeader.lua optional TableKit column header strip above the roster
      CharactersUI_Dialogs.lua      manual reorder + custom section dialogs
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager  -- Centralized font management
ns.CharactersUI = ns.CharactersUI or {}

local issecretvalue = issecretvalue

local function SafeLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

local function CompareCharNameLower(a, b)
    return SafeLower(a.name) < SafeLower(b.name)
end

-- Unique AceEvent handler identity for CharactersUI
local CharactersUIEvents = {}

-- Throttle WoW Token market request (C_WowTokenPublic.UpdateMarketPrice) â€” avoid per-tab-draw Blizzard work.
local _wnCharsTabLastTokenReq = 0
local WN_CHARS_TAB_TOKEN_REQ_INTERVAL = 600

-- Throttle lastSeen SavedVariables writes when reopening the Characters tab in one session.
local _wnCharsTabLastSeenBump = {}
local WN_CHARS_TAB_LAST_SEEN_INTERVAL = 90

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Import shared UI components (always get fresh reference)
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local FormatMoney = ns.UI_FormatMoney
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local BuildCollapsibleSectionOpts = ns.UI_BuildCollapsibleSectionOpts
local ApplyVisuals = ns.UI_ApplyVisuals
local FormatNumber = ns.UI_FormatNumber or function(n)
    return tostring(math.floor(tonumber(n) or 0))
end

local function ThemeTextHex(role)
    if ns.UI_GetTextRoleHex then
        return ns.UI_GetTextRoleHex(role)
    end
    if role == "Dim" then return "|cff888888" end
    if role == "Muted" then return "|cffaaaaaa" end
    return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
end

local function SemanticGoldHex()
    if ns.UI_GetSemanticGoldHex then
        return ns.UI_GetSemanticGoldHex()
    end
    return "|cffffd700"
end

--- Set row/cell text then refresh light-mode outline when markup or colored ink is present.
local function PresentFS(fs, text)
    if not fs then return end
    if text ~= nil and fs.SetText then
        fs:SetText(text)
    end
    if ns.UI_ApplyFontStringPresentation then
        local presentationText = text
        if presentationText == nil and fs.GetText then
            local got = fs:GetText()
            if not (issecretvalue and issecretvalue(got)) then
                presentationText = got
            end
        end
        ns.UI_ApplyFontStringPresentation(fs, presentationText)
    end
end

--- Section header count badge: role-colored count with standard FontManager outline.
local function SetSectionHeaderCount(fs, count, role)
    if not fs then return end
    ns.UI_SetTextColorRole(fs, role or "Muted")
    fs:SetText(FormatNumber(count or 0))
end
--- Per-section gold total for the built-in headers (Favorites / Character / Untracked). The anchor
--- is owned by UI_SetSectionHeaderGoldTotal (shared fixed column), so this must NOT re-anchor —
--- otherwise these totals would drift off the column the custom headers use.
local function AttachSectionGoldTotal(headerFrame, _countFs, list)
    if not headerFrame or not ns.UI_SetSectionHeaderGoldTotal then return end
    local CS = ns.CharacterService
    local copper = (CS and CS.SumCharacterListGold) and CS:SumCharacterListGold(list) or 0
    ns.UI_SetSectionHeaderGoldTotal(headerFrame, copper)
end
--- Delete-confirm dialog buttons: Factory + guarded chrome; classic skips custom hover backdrops.
local function ApplyCharDialogChrome(frame, bg, border)
    if not frame or not ApplyVisuals then return end
    if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(frame) then return end
    ApplyVisuals(frame, bg, border)
end
--- When `UI_CreateThemedButton` is missing, prefer Factory + ApplyCharDialogChrome; else legacy panel textures.
local function CreateCharacterDeleteDialogButton(parent, label, width, destructive)
    local themed = ns.UI_CreateThemedButton
    if themed then
        return themed(parent, label, width)
    end
    local Factory = ns.UI and ns.UI.Factory
    local ac = COLORS and COLORS.accent or { 0.4, 0.2, 0.58 }
    local ar, ag, ab = ac[1] or 0.4, ac[2] or 0.2, ac[3] or 0.58
    local btnH = 36
    if Factory and Factory.CreateButton then
        local btn = Factory:CreateButton(parent, width, btnH, false)
        if ApplyCharDialogChrome and (not ns.UI_CanApplyCustomChrome or ns.UI_CanApplyCustomChrome(btn)) then
            if destructive then
                ApplyCharDialogChrome(btn, { 0.22, 0.06, 0.07, 1 }, { 0.75, 0.18, 0.2, 1 })
            else
                ApplyCharDialogChrome(btn, { ar * 0.5, ag * 0.5, ab * 0.5, 1 }, { ar, ag, ab, 1 })
            end
        end
        if btn._wnBlizzardButton then
            if ns.UI_NormalizeBlizzardButtonChrome then
                ns.UI_NormalizeBlizzardButtonChrome(btn)
            end
        elseif Factory.ApplyHighlight then
            Factory:ApplyHighlight(btn)
        end
        local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
        btnText:SetPoint("CENTER")
        btnText:SetText(label)
        btn.text = btnText
        if ApplyCharDialogChrome and (not ns.UI_CanApplyCustomChrome or ns.UI_CanApplyCustomChrome(btn)) then
            if destructive then
                btn:SetScript("OnEnter", function(self)
                    ApplyCharDialogChrome(self, { 0.55, 0.1, 0.12, 1 }, { 0.95, 0.25, 0.28, 1 })
                end)
                btn:SetScript("OnLeave", function(self)
                    ApplyCharDialogChrome(self, { 0.22, 0.06, 0.07, 1 }, { 0.75, 0.18, 0.2, 1 })
                end)
            else
                btn:SetScript("OnEnter", function(self)
                    ApplyCharDialogChrome(self, { ar * 0.7, ag * 0.7, ab * 0.7, 1 }, { ar, ag, ab, 1 })
                end)
                btn:SetScript("OnLeave", function(self)
                    ApplyCharDialogChrome(self, { ar * 0.5, ag * 0.5, ab * 0.5, 1 }, { ar, ag, ab, 1 })
                end)
            end
        end
        return btn
    end
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, btnH)
    btn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    btn:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
    btnText:SetPoint("CENTER")
    btnText:SetText(label)
    return btn
end
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local CreateOnlineIndicator = ns.UI_CreateOnlineIndicator
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateIcon = ns.UI_CreateIcon -- Factory for icons
-- Pooling constants
local AcquireCharacterRow = ns.UI_AcquireCharacterRow
local ReleaseCharacterRow = ns.UI_ReleaseCharacterRow

--- Virtual-scroll tabs: refresh row culling after collapsible section layout (ReputationUI parity).
local function CharactersVirtualScrollBump()
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if not mf then return end
    -- Corner-drag: freeze list until resize commit (no interval column/gold/gradient churn).
    if ns.UI_IsMainFrameResizeSession and ns.UI_IsMainFrameResizeSession(mf) then
        return
    end
    if mf._virtualScrollUpdate then
        mf._virtualScrollUpdate()
    end
end

local GetCharKey = ns.UI_GetCharKey
local tinsert = table.insert

--- DB row key for the logged-in player (raw GetCharacterKey vs canonical SavedVariables key).
local function ResolveSessionCharactersTableKey()
    if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
        return ns.CharacterService:ResolveCharactersTableKey(WarbandNexus)
    end
    return nil
end

--- True if `char` list row is the current client session (fixes stale UI when row._key ~= GetCharacterKey()).
local function IsCharLoggedInSession(char)
    local rowKey = GetCharKey(char)
    if not rowKey then return false end
    local storage = ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    if storage and rowKey == storage then return true end
    local resolved = ResolveSessionCharactersTableKey()
    if resolved and rowKey == resolved then return true end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local canonRow = ns.Utilities:GetCanonicalCharacterKey(rowKey)
        if storage and canonRow == storage then return true end
        if resolved and canonRow == resolved then return true end
    end
    return false
end

local function GetLayout() return ns.UI_LAYOUT or {} end
local ROW_HEIGHT = GetLayout().rowHeight or 26
local ROW_SPACING = GetLayout().rowSpacing or 28
local HEADER_HEIGHT = GetLayout().HEADER_HEIGHT or 32
local HEADER_SPACING = GetLayout().headerSpacing or 44
local SECTION_SPACING = GetLayout().betweenSections or 8
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8

local function BuildGuildText(char, isCurrentCharacter)
    local guildName = (char and char.guildName) or nil
    if isCurrentCharacter then
        local liveGuild = IsInGuild() and GetGuildInfo("player") or nil
        if liveGuild and not (issecretvalue and issecretvalue(liveGuild)) then
            guildName = liveGuild
        end
    end

    if guildName and not (issecretvalue and issecretvalue(guildName)) and guildName ~= "" then
        return ThemeTextHex("Bright") .. guildName .. "|r"
    end

    return ThemeTextHex("Muted") .. "—|r"
end

local function RegisterCharacterEvents(parent)
    -- Register only once per parent
    if parent.characterUpdateHandler then
        return
    end
    parent.characterUpdateHandler = true
    
    -- WN_CHARACTER_UPDATED: REMOVED â€” UI.lua's SchedulePopulateContent already handles
    -- chars tab refresh via PopulateContent â†’ DrawCharacterList. Having both caused double rebuild.
    
    -- WN_CHARACTER_TRACKING_CHANGED refresh is centralized in UI.lua.
end

--- Reposition cached Characters fixedHeader chrome (Collections/Items _fixedHeaderCache parity — WN-PERF tab revisit).
local function RepositionCharactersFixedHeader(mf, hdrCache, headerParent, chrome, headerYOffset, contentSide, scrollChild)
    local titleCard = hdrCache.titleCard
    titleCard:SetParent(headerParent)
    local placedY
    if chrome and ns.UI_PageStack_Place then
        chrome.yOffset = headerYOffset
        placedY = ns.UI_PageStack_Place(chrome, titleCard)
    else
        titleCard:ClearAllPoints()
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    end
    titleCard:Show()
    if hdrCache.sortBtn then hdrCache.sortBtn:Show() end
    if titleCard._wnCharCustomSectionBtn then titleCard._wnCharCustomSectionBtn:Show() end
    if ns.UI_HideTitleCardExpandCollapseControls then
        ns.UI_HideTitleCardExpandCollapseControls(scrollChild)
    end
    if placedY then return placedY end
    if ns.UI_AdvanceTabChromeYOffset then
        return ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
    end
    return headerYOffset + (titleCard:GetHeight() or 64) + 8
end

function WarbandNexus:DrawCharacterList(parent)
    -- Request updated WoW Token market price (async) â€” heavily throttled; not tied to tab redraw frequency.
    if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice then
        local now = GetTime()
        if (now - _wnCharsTabLastTokenReq) >= WN_CHARS_TAB_TOKEN_REQ_INTERVAL then
            _wnCharsTabLastTokenReq = now
            C_WowTokenPublic.UpdateMarketPrice()
        end
    end

    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local width = (metrics and metrics.contentWidth)
        or (ns.UI_ResolveMainTabContentWidth and ns.UI_ResolveMainTabContentWidth(mf, parent))
        or (ns.UI_GetMainScrollContentWidth and mf and ns.UI_GetMainScrollContentWidth(mf))
        or (parent:GetWidth() or 600)

    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    local fixedHeader = mf and mf.fixedHeader
    local headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
    local headerYOffset = (chrome and chrome.yOffset) or (metrics and metrics.topMargin) or TOP_MARGIN
    local contentSide = (chrome and chrome.side) or (metrics and metrics.sideMargin) or SIDE_MARGIN
    local sectionGap = (GetLayout().PAGE_STACK and GetLayout().PAGE_STACK.SECTION_GAP) or (metrics and metrics.sectionGap) or SECTION_SPACING
    
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "db.global.characters"
        if self.db.global.characterCache and next(self.db.global.characterCache.characters or {}) then
            local cacheVersion = self.db.global.characterCache.version or "unknown"
            dataSource = "CharacterCache v" .. cacheVersion
        end
        parent.dbVersionBadge = CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Register event listener (only once)
    RegisterCharacterEvents(parent)
    
    -- Hide empty state card (will be shown again if needed)
    HideEmptyStateCard(parent, "characters")

    -- Paths always reach PopulateContent today; still mirror Storage/Reputation so future callers stay safe.
    local mfForVirtual = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfForVirtual and ns.VirtualListModule and ns.VirtualListModule.ClearVirtualScroll then
        if not parent._preparedByPopulate then
            ns.VirtualListModule.ClearVirtualScroll(mfForVirtual)
        end
    end

    -- Nested character rows: PopulateContent walks subtrees via UI_ReleaseCharacterRowsFromSubtree before recycle.
    
    local currentPlayerKey = ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    local sessionTableKey = ResolveSessionCharactersTableKey() or currentPlayerKey
    if self.db.global.characters and sessionTableKey and self.db.global.characters[sessionTableKey] then
        local now = GetTime()
        local last = _wnCharsTabLastSeenBump[sessionTableKey] or 0
        if (now - last) >= WN_CHARS_TAB_LAST_SEEN_INTERVAL then
            _wnCharsTabLastSeenBump[sessionTableKey] = now
            self.db.global.characters[sessionTableKey].lastSeen = time()
        end
    end
    
    local characters = self:GetAllCharacters()

    local CHAR_TITLE_RIGHT_RESERVE = (ns.UI_ComputeCharactersTitleToolbarReserve and ns.UI_ComputeCharactersTitleToolbarReserve())
        or 256
    local subtitleLine = (ns.L and ns.L["CHARACTERS_SUBTITLE"])
        or "A scrollable list of your characters with gold, level, gear, and key stats in one place."

    local hdrCache = mf and mf._charsFixedHeaderCache
    local headerDone = false
    local sortBtn

    if hdrCache and hdrCache.titleCard then
        headerYOffset = RepositionCharactersFixedHeader(mf, hdrCache, headerParent, chrome, headerYOffset, contentSide, parent)
        if ns.UI_CommitTabFixedHeader then
            ns.UI_CommitTabFixedHeader(mf, headerYOffset)
        elseif fixedHeader then
            fixedHeader:SetHeight(headerYOffset)
        end
        headerDone = true
    end

    if not headerDone then
    local titleCard, headerIcon, titleTextContainer, titleText, subtitleText = ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "characters",
        titleText = (ns.L and ns.L["YOUR_CHARACTERS"]) or "Your Characters",
        subtitleText = subtitleLine,
        textRightInset = CHAR_TITLE_RIGHT_RESERVE,
    })
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        local contentSide = (metrics and metrics.sideMargin) or SIDE_MARGIN
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    end

    local titleControlInset = (ns.UI_SPACING and ns.UI_SPACING.TITLE_CARD_TOOLBAR_EDGE_INSET) or 0

    -- Sort dropdown anchors at card top-right; expand/collapse sit to its left (no overlap).
    local sortAnchorFrame = titleCard
    local sortAnchorPoint = "RIGHT"
    local sortAnchorX = -titleControlInset

    if ns.UI_CreateCharacterTabAdvancedFilterButton then
        if ns.CharacterService and ns.CharacterService.EnsureCustomCharacterSectionsProfile then
            ns.CharacterService:EnsureCustomCharacterSectionsProfile(self.db.profile)
        end
        local sortOptions = (ns.UI_BuildCharacterSortOptions and ns.UI_BuildCharacterSortOptions())
            or {}
        if not self.db.profile.characterSort then self.db.profile.characterSort = {} end
        if not self.db.profile.characterSectionFilter then self.db.profile.characterSectionFilter = { sectionKey = "all" } end
        sortBtn = ns.UI_CreateCharacterTabAdvancedFilterButton(titleCard, {
            sortOptions = sortOptions,
            dbSortTable = self.db.profile.characterSort,
            sortTabId = "characters",
            dbSectionFilter = self.db.profile.characterSectionFilter,
            getCustomSections = function()
                return self.db.profile.characterCustomGroups or {}
            end,
            onRefresh = function()
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
            end,
            onDeleteSection = function(groupId, groupName)
                WarbandNexus:ConfirmDeleteCustomCharacterHeader(groupId, groupName)
            end,
        })
        if sortBtn then
            if ns.UI_AnchorTitleCardToolbarControl then
                ns.UI_AnchorTitleCardToolbarControl(sortBtn, titleCard, titleCard, "RIGHT", -titleControlInset)
            else
                sortBtn:ClearAllPoints()
                sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleControlInset, 0)
            end
            sortBtn:SetFrameLevel(titleCard:GetFrameLevel() + 5)
            -- Match Filter row height (Factory advanced filter uses BUTTON_HEIGHT).
            local sectionToolbarBtnSize = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
            -- Visible entry for custom sections: same footprint as Filter, left of it.
            local secQuick = titleCard._wnCharCustomSectionBtn
            if not secQuick and ns.UI and ns.UI.Factory and ns.UI.Factory.CreateButton then
                secQuick = ns.UI.Factory:CreateButton(titleCard, sectionToolbarBtnSize, sectionToolbarBtnSize, true)
                titleCard._wnCharCustomSectionBtn = secQuick
                secQuick:SetFrameLevel(titleCard:GetFrameLevel() + 6)
                if secQuick.RegisterForClicks then
                    secQuick:RegisterForClicks("LeftButtonUp")
                end
                local okAtlas = false
                if secQuick.SetNormalAtlas then
                    okAtlas = pcall(function()
                        secQuick:SetNormalAtlas("GM-icon-assistActive-hover")
                    end)
                end
                if not okAtlas then
                    local tex = (secQuick.GetNormalTexture and secQuick:GetNormalTexture())
                    if tex then
                        tex:SetTexture("Interface\\Icons\\Achievement_Reputation_08")
                        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    end
                end
                secQuick:SetScript("OnClick", function(btn)
                    if ns.UI_ShowCharacterSectionsToolbarMenu then
                        ns.UI_ShowCharacterSectionsToolbarMenu(btn, WarbandNexus.db.profile)
                    elseif WarbandNexus.OpenCustomCharacterHeaderDialog then
                        WarbandNexus:OpenCustomCharacterHeaderDialog()
                    end
                end)
                secQuick:SetScript("OnEnter", function(btn)
                    GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMRIGHT")
                    GameTooltip:SetText((ns.L and ns.L["CUSTOM_HEADER_TITLEBAR_BTN_TOOLTIP"]) or "Custom sections", 1, 1, 1)
                    GameTooltip:AddLine((ns.L and ns.L["CUSTOM_HEADER_TITLEBAR_BTN_TOOLTIP_BODY"]) or "Open the menu: new or delete headers, gold-style section, or use [+] on a header to add characters.", 0.85, 0.85, 0.9, true)
                    GameTooltip:Show()
                end)
                secQuick:SetScript("OnLeave", GameTooltip_Hide)
            elseif secQuick then
                secQuick:SetSize(sectionToolbarBtnSize, sectionToolbarBtnSize)
            end
            if titleCard._wnCharCustomSectionBtn then
                if ns.UI_AnchorTitleCardToolbarControl then
                    ns.UI_AnchorTitleCardToolbarControl(titleCard._wnCharCustomSectionBtn, titleCard, sortBtn, "LEFT", -8)
                else
                    titleCard._wnCharCustomSectionBtn:ClearAllPoints()
                    titleCard._wnCharCustomSectionBtn:SetPoint("RIGHT", sortBtn, "LEFT", -8, 0)
                end
                titleCard._wnCharCustomSectionBtn:Show()
                sortAnchorFrame = titleCard._wnCharCustomSectionBtn
            else
                sortAnchorFrame = sortBtn
            end
            sortAnchorPoint = "LEFT"
            sortAnchorX = -10
        end
    elseif ns.UI_CreateCharacterSortDropdown then
        if titleCard._wnCharCustomSectionBtn then
            titleCard._wnCharCustomSectionBtn:Hide()
        end
        local sortOptions = (ns.UI_BuildCharacterSortOptions and ns.UI_BuildCharacterSortOptions())
            or {}
        if not self.db.profile.characterSort then self.db.profile.characterSort = {} end
        sortBtn = ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.characterSort, function()
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end, "characters")
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(sortBtn, titleCard, titleCard, "RIGHT", -titleControlInset)
        else
            sortBtn:ClearAllPoints()
            sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleControlInset, 0)
        end
        sortBtn:SetFrameLevel(titleCard:GetFrameLevel() + 5)
        sortAnchorFrame = sortBtn
        sortAnchorPoint = "LEFT"
        sortAnchorX = -10
    end

    if ns.UI_HideTitleCardExpandCollapseControls then
        ns.UI_HideTitleCardExpandCollapseControls(parent)
    end

    -- NO TRACKING: Static text, never overflows
    
    titleCard:Show()
    if chrome and ns.UI_PageStack_Place then
        -- Same helper as RepositionCharactersFixedHeader (cached revisit) so both paths stay identical.
        chrome.yOffset = headerYOffset
        headerYOffset = ns.UI_PageStack_Place(chrome, titleCard)
    elseif ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
    else
        headerYOffset = headerYOffset + (titleCard:GetHeight() or 64) + 8
    end
    if ns.UI_CommitTabFixedHeader then
        ns.UI_CommitTabFixedHeader(mf, headerYOffset)
    elseif fixedHeader then
        fixedHeader:SetHeight(headerYOffset)
    end

    if mf then
        mf._charsFixedHeaderCache = {
            titleCard = titleCard,
            sortBtn = sortBtn,
        }
    end
    end -- not headerDone

    -- PAGE_STACK.BODY_TOP: title card -> first gold card = BLOCK_GAP + BODY_TOP (16), like every tab.
    local yOffset = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8

    -- Get current character's gold (live bag total for session toon; DB for alts).
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
    local currentCharGold = ns.Utilities:GetLiveCharacterMoneyCopper(0)
    local isLoadingCharacterData = false
    
    -- Check if character data is being loaded (SaveCharacter in progress)
    if isTracked then
        local dbKey = sessionTableKey or currentPlayerKey
        if not dbKey or not self.db.global.characters[dbKey] then
            isLoadingCharacterData = true
        elseif not self.db.global.characters[dbKey].gold then
            isLoadingCharacterData = true
        end
    end
    
    local totalCharGold = 0
    
    for i = 1, #characters do
        local char = characters[i]
        local charGold = ns.Utilities:GetCharTotalCopper(char)
        
        if IsCharLoggedInSession(char) then
            -- Use real-time gold for current character (if tracked)
            totalCharGold = totalCharGold + currentCharGold
        else
            -- Use cached gold for other characters
            totalCharGold = totalCharGold + charGold
        end
    end
    
    local warbandBankGold = ns.Utilities:GetWarbandBankMoney() or 0
    local totalWithWarband = totalCharGold + warbandBankGold
    
    -- Three equal gold summary cards must occupy the SAME [side .. side+rowWidth] band as the
    -- section headers and character rows. The card layout carves leftMargin+rightMargin out of
    -- hostW and splits the remainder three ways, so hostW = rowDrawWidth + those two margins;
    -- passing the raw row width left the cards 2*side too narrow (visibly inset from the headers).
    local leftMargin = contentSide
    local rightMargin = contentSide
    local cardSpacing = (GetLayout().PAGE_STACK and GetLayout().PAGE_STACK.CARD_GAP) or 10
    local rowScrollW = ns.UI_ResolveCharactersTabRowWidth
        and ns.UI_ResolveCharactersTabRowWidth(mf, parent, metrics, self._charListMaxGuildWidth)
    local hostW
    if rowScrollW and rowScrollW > 0 then
        hostW = rowScrollW + leftMargin + rightMargin
    else
        hostW = (metrics and metrics.contentWidth)
            or (mf and ns.UI_GetMainTabViewportWidth and ns.UI_GetMainTabViewportWidth(mf))
            or (parent.GetWidth and parent:GetWidth())
            or width
            or 600
    end
    local gm = ns.CharactersUI.ComputeCharactersGoldCardMetrics(hostW, leftMargin, rightMargin, cardSpacing)
    local stackGoldCards = gm.stackGoldCards
    local stackGoldTokenInCard3 = gm.stackGoldTokenInCard3
    local goldCardW1 = gm.goldCardW1
    local goldCardW2 = gm.goldCardW2
    local goldCardW3 = gm.goldCardW3
    local card12H = gm.card12H
    local card3H = gm.card3H

    local CreateCardHeaderLayout = ns.UI_CreateCardHeaderLayout
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon

    local goldDisplayText = isLoadingCharacterData
        and (ThemeTextHex("Dim") .. ((ns.L and ns.L["LOADING"]) or "Loading...") .. "|r")
        or FormatMoney(currentCharGold, 14)
    local charIconTex = GetCharacterSpecificIcon()

    -- PERSISTENT CARD TRIO: the gold summary repaints on every CHARACTER_UPDATED
    -- (gold ticks), and recreating three cards + children each time was the hottest
    -- chrome-churn path in the addon. The bundle (already maintained for the viewport
    -- adapter) now also carries the frames; teardown parks them in the recycle bin
    -- and we re-adopt here. A character-icon change (rare) rebuilds from scratch.
    local bundle = parent._wnCharsGoldBundle
    if bundle and bundle.charIconTex ~= charIconTex then
        local bin = ns.UI_RecycleBin
        for _, f in ipairs({ bundle.char, bundle.wb, bundle.total }) do
            if f then f:Hide(); f:ClearAllPoints(); if bin then f:SetParent(bin) end end
        end
        bundle = nil
        parent._wnCharsGoldBundle = nil
    end

    local charGoldCard, wbGoldCard, totalGoldCard

    if bundle then
        -- REUSE: re-adopt and update texts only.
        charGoldCard, wbGoldCard, totalGoldCard = bundle.char, bundle.wb, bundle.total
        charGoldCard:SetParent(parent)
        wbGoldCard:SetParent(parent)
        totalGoldCard:SetParent(parent)
        if bundle.cg1Value then bundle.cg1Value:SetText(goldDisplayText); PresentFS(bundle.cg1Value) end
        if bundle.wb1Value then bundle.wb1Value:SetText(FormatMoney(warbandBankGold, 14)); PresentFS(bundle.wb1Value) end
        if bundle.tgValue then bundle.tgValue:SetText(FormatMoney(totalWithWarband, 14)); PresentFS(bundle.tgValue) end
        -- Spinner lifecycle matters now that the card persists across paints.
        if isLoadingCharacterData and bundle.cg1Value then
            if charGoldCard.loadingSpinner then
                charGoldCard.loadingSpinner:Show()
            elseif ns.UI_CreateInlineLoadingSpinner then
                charGoldCard.loadingSpinner = ns.UI_CreateInlineLoadingSpinner(
                    charGoldCard, bundle.cg1Value, "LEFT", bundle.cg1Value:GetStringWidth() + 4, 0, 16)
            end
        elseif charGoldCard.loadingSpinner then
            charGoldCard.loadingSpinner:Hide()
        end
        bundle.yOffset = yOffset
        bundle.leftMargin = leftMargin
        bundle.rightMargin = rightMargin
        bundle.cardSpacing = cardSpacing
        bundle._gm = gm
    else

    -- Characters Gold Card (left)
    charGoldCard = CreateCard(parent, card12H)

    local cg1Layout = CreateCardHeaderLayout(
        charGoldCard,
        charIconTex,
        40,
        true,
        (ns.L and ns.L["HEADER_CURRENT_CHARACTER"]) or "CURRENT CHARACTER",
        goldDisplayText,
        "subtitle",
        "body"
    )

    -- Add inline loading spinner if data is being collected (Factory pattern)
    if isLoadingCharacterData and cg1Layout.value then
        local UI_CreateInlineLoadingSpinner = ns.UI_CreateInlineLoadingSpinner
        if UI_CreateInlineLoadingSpinner then
            charGoldCard.loadingSpinner = UI_CreateInlineLoadingSpinner(
                charGoldCard,
                cg1Layout.value,
                "LEFT",
                cg1Layout.value:GetStringWidth() + 4,
                0,
                16
            )
        end
    end

    -- NO TRACKING: Numbers rarely overflow (formatted gold)

    -- Warband Gold Card (middle)
    wbGoldCard = CreateCard(parent, card12H)
    
    -- Use factory for standardized card header layout
    local wb1Layout = CreateCardHeaderLayout(
        wbGoldCard,
        "warbands-icon",
        40,
        true,
        (ns.L and ns.L["HEADER_WARBAND_GOLD"]) or "WARBAND GOLD",
        FormatMoney(warbandBankGold, 14),
        "subtitle",
        "body"
    )
    
    -- NO TRACKING: Numbers rarely overflow (formatted gold)

    -- Total Gold + Token Card (right; same width as siblings in row mode)
    totalGoldCard = CreateCard(parent, card3H)

    -- Vertical divider (hidden when Total Gold + Token are stacked)
    local divider = totalGoldCard:CreateTexture(nil, "ARTWORK")
    divider:SetSize(1, 50)
    local divBorder = ns.UI_GetBorderStrokeColor and ns.UI_GetBorderStrokeColor() or COLORS.border
    divider:SetColorTexture(divBorder[1], divBorder[2], divBorder[3], 0.45)

    -- Left block: Total Gold (icon + label + value)
    local tgIcon = CreateIcon(totalGoldCard, "BonusLoot-Chest", 36, true, nil, true)
    tgIcon:Show()

    local tgTextContainer = (ns.UI.Factory and ns.UI.Factory:CreateContainer(totalGoldCard, 220, 64, false))
        or CreateFrame("Frame", nil, totalGoldCard)

    local tgLabel = FontManager:CreateFontString(tgTextContainer, "subtitle", "OVERLAY")
    tgLabel:SetText((ns.L and ns.L["HEADER_TOTAL_GOLD"]) or "TOTAL GOLD")
    ns.UI_SetTextColorRole(tgLabel, "Bright")
    tgLabel:SetJustifyH("LEFT")
    tgLabel:SetPoint("BOTTOM", tgTextContainer, "CENTER", 0, 0)
    tgLabel:SetPoint("LEFT", tgTextContainer, "LEFT", 0, 0)

    local tgValue = FontManager:CreateFontString(tgTextContainer, "body", "OVERLAY")
    tgValue:SetText(FormatMoney(totalWithWarband, 14))  -- updated in the reuse branch on later paints
    tgValue:SetJustifyH("LEFT")
    tgValue:SetPoint("TOP", tgTextContainer, "CENTER", 0, -4)
    tgValue:SetPoint("LEFT", tgTextContainer, "LEFT", 0, 0)
    -- RIGHT clamp: without it, large gold strings grew past the container and
    -- overlapped the divider/token block at intermediate card widths.
    tgValue:SetPoint("RIGHT", tgTextContainer, "RIGHT", 0, 0)
    tgValue:SetWordWrap(false)
    tgValue:SetNonSpaceWrap(false)

    -- Right block: WoW Token (icon + label + price with token count)
    local tkIcon = totalGoldCard:CreateTexture(nil, "ARTWORK")
    tkIcon:SetSize(28, 28)
    tkIcon:SetTexture("Interface\\Icons\\WoW_Token01")
    tkIcon:Show()

    local tkTextContainer = (ns.UI.Factory and ns.UI.Factory:CreateContainer(totalGoldCard, 220, 64, false))
        or CreateFrame("Frame", nil, totalGoldCard)

    local tkLabel = FontManager:CreateFontString(tkTextContainer, "subtitle", "OVERLAY")
    tkLabel:SetText((ns.L and ns.L["WOW_TOKEN_LABEL"]) or "WOW TOKEN")
    ns.UI_SetTextColorRole(tkLabel, "Bright")
    tkLabel:SetJustifyH("LEFT")
    tkLabel:SetPoint("BOTTOM", tkTextContainer, "CENTER", 0, 0)
    tkLabel:SetPoint("LEFT", tkTextContainer, "LEFT", 0, 0)

    local tkValue = FontManager:CreateFontString(tkTextContainer, "body", "OVERLAY")
    tkValue:SetJustifyH("LEFT")
    tkValue:SetPoint("TOP", tkTextContainer, "CENTER", 0, -4)
    tkValue:SetPoint("LEFT", tkTextContainer, "LEFT", 0, 0)
    tkValue:SetPoint("RIGHT", tkTextContainer, "RIGHT", 0, 0)
    tkValue:SetWordWrap(false)
    tkValue:SetNonSpaceWrap(false)

    parent._wnCharsGoldBundle = {
        parent = parent,
        char = charGoldCard,
        wb = wbGoldCard,
        total = totalGoldCard,
        yOffset = yOffset,
        leftMargin = leftMargin,
        rightMargin = rightMargin,
        cardSpacing = cardSpacing,
        divider = divider,
        tgIcon = tgIcon,
        tgTextContainer = tgTextContainer,
        tkIcon = tkIcon,
        tkTextContainer = tkTextContainer,
        midRule = nil,
        _gm = gm,
        -- Reuse-path references (see the persistent-trio branch above)
        charIconTex = charIconTex,
        cg1Value = cg1Layout.value,
        wb1Value = wb1Layout.value,
        tgValue = tgValue,
        tkValue = tkValue,
    }
    end -- persistent card trio: create/reuse split

    bundle = parent._wnCharsGoldBundle

    -- COMMON LAYOUT (runs for both fresh and reused cards): metrics can change
    -- between paints (resize, stack-mode flip), so size and anchor every time.
    charGoldCard:SetSize(goldCardW1, card12H)
    charGoldCard:ClearAllPoints()
    charGoldCard:SetPoint("TOPLEFT", parent, "TOPLEFT", leftMargin, -yOffset)
    wbGoldCard:SetSize(goldCardW2, card12H)
    wbGoldCard:ClearAllPoints()
    if stackGoldCards then
        wbGoldCard:SetPoint("TOPLEFT", charGoldCard, "BOTTOMLEFT", 0, -cardSpacing)
    else
        wbGoldCard:SetPoint("TOPLEFT", charGoldCard, "TOPRIGHT", cardSpacing, 0)
    end
    totalGoldCard:SetSize(goldCardW3, card3H)
    totalGoldCard:ClearAllPoints()
    if stackGoldCards then
        totalGoldCard:SetPoint("TOPLEFT", wbGoldCard, "BOTTOMLEFT", 0, -cardSpacing)
    else
        totalGoldCard:SetPoint("TOPLEFT", wbGoldCard, "TOPRIGHT", cardSpacing, 0)
    end

    ns.CharactersUI.ApplyTotalGoldCardInterior(bundle, stackGoldTokenInCard3)

    -- GetCurrentMarketPrice updates asynchronously after UpdateMarketPrice();
    -- TOKEN_MARKET_PRICE_UPDATED refreshes the tab (Core.lua).
    local tokenPrice = C_WowTokenPublic and C_WowTokenPublic.GetCurrentMarketPrice and select(1, C_WowTokenPublic.GetCurrentMarketPrice())
    local tkValueRef = bundle.tkValue
    if tokenPrice and tokenPrice > 0 then
        local affordableCount = math.floor(totalWithWarband / tokenPrice)
        tkValueRef:SetText(
            FormatMoney(tokenPrice, 12)
                .. "  |cff66c0ff("
                .. affordableCount
                .. " "
                .. (((ns.L and ns.L["WOW_TOKEN_COUNT_LABEL"]) or "Tokens"))
                .. ")|r"
        )
        PresentFS(tkValueRef)
    else
        tkValueRef:SetText(ThemeTextHex("Dim") .. ((ns.L and ns.L["NOT_AVAILABLE_SHORT"]) or "N/A") .. "|r")
        PresentFS(tkValueRef)
        -- One-shot retry if price not ready yet (event-driven path is primary).
        if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice then
            C_Timer.After(1.25, function()
                local addon = _G.WarbandNexus
                if not addon or not addon.UI or not addon.UI.mainFrame then return end
                local mf = addon.UI.mainFrame
                if not mf:IsShown() or mf.currentTab ~= "chars" then return end
                local p = select(1, C_WowTokenPublic.GetCurrentMarketPrice and C_WowTokenPublic.GetCurrentMarketPrice() or 0)
                if p and p > 0 and addon.SendMessage then
                    addon:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "chars", skipCooldown = true })
                end
            end)
        end
    end

    charGoldCard:Show()
    wbGoldCard:Show()
    totalGoldCard:Show()

    if stackGoldCards then
        yOffset = yOffset + card12H + cardSpacing + card12H + cardSpacing + card3H + sectionGap
    else
        yOffset = yOffset + math.max(card12H, card3H) + sectionGap
    end

    if not self.db.profile.ui then self.db.profile.ui = {} end
    local staleCopies = (ns.CharacterService and ns.CharacterService.FindProbableStaleCharacterCopies)
        and ns.CharacterService:FindProbableStaleCharacterCopies(self) or {}
    if #staleCopies > 0 and not self.db.profile.ui.dismissStaleCharacterCopiesBanner then
        local bannerH = 52
        -- CreateCard(parent, height): the old 4-arg call passed contentSide (~12px)
        -- as the height, squashing the stale-copies banner to a sliver.
        local banner = CreateCard(parent, bannerH)
        banner:ClearAllPoints()
        banner:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -yOffset)
        banner:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -contentSide, -yOffset)
        local goldC = COLORS.gold or { 1, 0.82, 0, 1 }
        local bannerBg = (ns.UI_ResolveSurfaceTierColor and ns.UI_ResolveSurfaceTierColor("card"))
            or COLORS.bgCard or COLORS.bgLight or COLORS.bg
        if ApplyVisuals then
            ApplyVisuals(banner, bannerBg, { goldC[1], goldC[2], goldC[3], 0.82 })
        end
        local bannerTitle = FontManager:CreateFontString(banner, "header", "OVERLAY")
        bannerTitle:SetPoint("TOPLEFT", 12, -8)
        bannerTitle:SetPoint("RIGHT", banner, "RIGHT", -90, 0)
        bannerTitle:SetJustifyH("LEFT")
        bannerTitle:SetText(SemanticGoldHex() .. ((ns.L and ns.L["STALE_CHARACTER_COPIES_TITLE"]) or "Duplicate character entries") .. "|r")
        local bannerBody = FontManager:CreateFontString(banner, "body", "OVERLAY")
        bannerBody:SetPoint("TOPLEFT", bannerTitle, "BOTTOMLEFT", 0, -2)
        bannerBody:SetPoint("RIGHT", banner, "RIGHT", -90, 0)
        bannerBody:SetJustifyH("LEFT")
        bannerBody:SetWordWrap(true)
        bannerBody:SetMaxLines(2)
        ns.UI_SetTextColorRole(bannerBody, "Normal")
        bannerBody:SetText((ns.L and ns.L["STALE_CHARACTER_COPIES_DESC"]) or "Delete old copies or use the tracking icon.")
        local dismissBtn = ns.UI.Factory:CreateButton(banner, 72, 24, false)
        dismissBtn:SetPoint("RIGHT", banner, "RIGHT", -8, 0)
        local dismissBg = (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop())
            or COLORS.bgCard or COLORS.bgLight or COLORS.bg
        local dismissBr = COLORS.accent or { 0.4, 0.2, 0.58 }
        if ApplyVisuals then
            ApplyVisuals(dismissBtn, dismissBg, { dismissBr[1], dismissBr[2], dismissBr[3], 0.65 })
        end
        local dismissLabel = FontManager:CreateFontString(dismissBtn, "body", "OVERLAY")
        dismissLabel:SetPoint("CENTER")
        dismissLabel:SetText((ns.L and ns.L["STALE_CHARACTER_COPIES_DISMISS"]) or "Dismiss")
        dismissBtn:SetScript("OnClick", function()
            self.db.profile.ui.dismissStaleCharacterCopiesBanner = true
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "chars", skipCooldown = true })
        end)
        yOffset = yOffset + bannerH + sectionGap
    end
    
    local sortOptions = (ns.UI_BuildCharacterSortOptions and ns.UI_BuildCharacterSortOptions())
        or {}
    
    if not self.db.profile.characterSort then self.db.profile.characterSort = {} end
    local currentSortKey = (ns.CharacterService and ns.CharacterService.GetTabSortKey)
        and ns.CharacterService:GetTabSortKey(self.db.profile, "characters")
        or "default"

    local sectionFilter = "all"
    if self.db.profile.characterSectionFilter and type(self.db.profile.characterSectionFilter.sectionKey) == "string" then
        sectionFilter = self.db.profile.characterSectionFilter.sectionKey
    end
    if ns.CharacterService and ns.CharacterService.EnsureCustomCharacterSectionsProfile then
        ns.CharacterService:EnsureCustomCharacterSectionsProfile(self.db.profile)
    end

    local favoriteKeySet = (ns.CharacterService and ns.CharacterService.BuildFavoriteKeySet)
        and ns.CharacterService:BuildFavoriteKeySet(self) or {}
    
    local trackedFavorites = {}
    local trackedRegular = {}
    local untracked = {}

    -- Custom header buckets must exist before the split: a section wins over Favorites, so a
    -- favorited character assigned to a section renders there with its star, not in Favorites.
    local customGroupsOrdered = (ns.CharacterService and ns.CharacterService.BuildOrderedCustomCharacterGroups)
        and ns.CharacterService:BuildOrderedCustomCharacterGroups(self.db.profile, currentSortKey)
        or (self.db.profile.characterCustomGroups or {})
    local assignments = self.db.profile.characterGroupAssignments or {}
    local groupedById = {}
    for gi = 1, #customGroupsOrdered do
        groupedById[customGroupsOrdered[gi].id] = {}
    end

    for i = 1, #characters do
        local char = characters[i]
        local charKey = GetCharKey(char)
        local isTracked = char.isTracked ~= false  -- Default to true if not set

        -- Separate by tracking status first, then section, then favorites
        if not isTracked then
            tinsert(untracked, char)
        elseif ns.CharacterService then
            local isFav = (ns.CharacterService.IsFavoriteFromKeySet and ns.CharacterService:IsFavoriteFromKeySet(favoriteKeySet, charKey))
                or ns.CharacterService:IsFavoriteCharacter(self, charKey)
            local gid = nil
            if charKey and ns.CharacterService.GetCharacterCustomSectionId then
                gid = ns.CharacterService:GetCharacterCustomSectionId(self, charKey)
            elseif charKey then
                gid = assignments[charKey]
            end
            if gid and groupedById[gid] then
                tinsert(groupedById[gid], char)
            elseif isFav then
                tinsert(trackedFavorites, char)
            else
                tinsert(trackedRegular, char)
            end
        end
    end

    -- Load custom order from profile
    if not self.db.profile.characterOrder then
        self.db.profile.characterOrder = {
            favorites = {},
            regular = {},
            untracked = {}
        }
    end
    
    -- Sort function (with custom order support)
    local function sortCharacters(list, orderKey)
        local CS = ns.CharacterService
        if CS and CS.SortCharacterRosterList then
            return CS:SortCharacterRosterList(list, self.db.profile, orderKey, {
                tabId = "characters",
                compareNameFn = CompareCharNameLower,
                isLoggedInFn = IsCharLoggedInSession,
                getCharKeyFn = GetCharKey,
            })
        end
        table.sort(list, function(a, b)
            return CompareCharNameLower(a, b)
        end)
        return list
    end
    
    -- Sort favorites, each custom header bucket, ungrouped regular, then untracked
    trackedFavorites = sortCharacters(trackedFavorites, "favorites")
    for gi = 1, #customGroupsOrdered do
        local gid = customGroupsOrdered[gi].id
        local list = groupedById[gid]
        if list then
            local lk = (ns.CharacterService and ns.CharacterService.GetCustomGroupListKey and ns.CharacterService:GetCustomGroupListKey(gid)) or ("group_" .. tostring(gid))
            sortCharacters(list, lk)
            if ns.CharacterService and ns.CharacterService.PartitionFavoritesFirst then
                ns.CharacterService:PartitionFavoritesFirst(self, list, GetCharKey)
            end
        end
    end
    trackedRegular = sortCharacters(trackedRegular, "regular")
    untracked = sortCharacters(untracked, "untracked")
    
    -- Guild column width: max guild name width across all visible characters (centered text)
    do
        if not parent.guildMeasureFs then
            parent.guildMeasureFs = FontManager:CreateFontString(parent, "body", "OVERLAY")
            parent.guildMeasureFs:Hide()
        end
        local fs = parent.guildMeasureFs
        local maxW = 0
        local GUILD_PADDING = 20
        local GUILD_MIN = 60
        local GUILD_MAX = 280
        local rawCap = GUILD_MAX - GUILD_PADDING
        local listsToMeasure = { trackedFavorites, trackedRegular, untracked }
        for gmi = 1, #customGroupsOrdered do
            local gmid = customGroupsOrdered[gmi].id
            if groupedById[gmid] then tinsert(listsToMeasure, groupedById[gmid]) end
        end
        for li = 1, #listsToMeasure do
            local list = listsToMeasure[li]
            for i = 1, #list do
                local char = list[i]
                local isCurrent = IsCharLoggedInSession(char)
                fs:SetText(BuildGuildText(char, isCurrent))
                local w = fs:GetStringWidth()
                if w > maxW then maxW = w end
                if maxW >= rawCap then
                    break
                end
            end
            if maxW >= rawCap then
                break
            end
        end
        self._charListMaxGuildWidth = math.min(math.max(maxW + GUILD_PADDING, GUILD_MIN), GUILD_MAX)
    end

    local rowDrawWidth = width
    if ns.UI_ResolveCharactersTabRowWidth then
        rowDrawWidth = ns.UI_ResolveCharactersTabRowWidth(mf, parent, metrics, self._charListMaxGuildWidth)
    end
    local sectionStackW = math.max(1, rowDrawWidth or width or 1)
    parent._charsSectionStackW = sectionStackW
    if mf then
        -- scrollChild floor must be the OUTER width: rows/headers/gold anchor at contentSide and span
        -- sectionStackW, so the scroll content needs contentSide on BOTH sides (matches PvE/PvP/Prof/Gear,
        -- whose min-scroll widths already include 2*side). Without this the right margin collapses and the
        -- list runs under the vertical scrollbar lane.
        mf._charsMinScrollWidth = math.max(1, sectionStackW + contentSide * 2)
    end
    if ns.UI_ComputeCharRowGuildColumnWidth then
        self._charsListStableGuildColW = ns.UI_ComputeCharRowGuildColumnWidth(rowDrawWidth, self._charListMaxGuildWidth)
    else
        self._charsListStableGuildColW = self._charListMaxGuildWidth
    end
    
    if #characters == 0 then
        local _, height = CreateEmptyStateCard(parent, "characters", yOffset)
        return yOffset + height
    end
    
    -- Initialize collapse state (persistent)
    if not self.db.profile.ui then
        self.db.profile.ui = {}
    end
    if self.db.profile.ui.favoritesExpanded == nil then
        self.db.profile.ui.favoritesExpanded = true
    end
    if self.db.profile.ui.charactersExpanded == nil then
        self.db.profile.ui.charactersExpanded = true
    end
    
    local SECTION_H = (GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT) or 36
    local SECTION_HEADER_GAP = sectionGap or 12  -- PAGE_STACK.SECTION_GAP between section blocks
    local SECTION_HEADER_TEXT_INSET = 12
    local previousSectionContent = nil
    local isFirstSection = true

    -- Optional column header strip (TableKit, display-only) directly above the first section.
    if ns.CharactersUI.PlaceCharactersColumnHeader and ns.CharactersUI.IsCharactersColumnHeaderEnabled(self.db.profile) then
        yOffset = ns.CharactersUI.PlaceCharactersColumnHeader(parent, yOffset, contentSide, sectionStackW, SECTION_HEADER_GAP)
    end

    local function AcquireSectionContentFrame(anchorHeader)
        local contentFrame = nil
        local hostW = math.max(1, sectionStackW or width or (parent.GetWidth and parent:GetWidth()) or 1)
        if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateContainer then
            -- Parent = section header so virtual-scroll offset walks header -> scrollChild correctly.
            contentFrame = ns.UI.Factory:CreateContainer(anchorHeader, hostW, 1, false)
        else
            contentFrame = CreateFrame("Frame", nil, anchorHeader)
            contentFrame:SetSize(hostW, 1)
        end

        contentFrame:ClearAllPoints()
        contentFrame:SetPoint("TOPLEFT", anchorHeader, "BOTTOMLEFT", 0, 0)
        contentFrame:SetPoint("TOPRIGHT", anchorHeader, "BOTTOMRIGHT", 0, 0)
        contentFrame:SetHeight(0.1)
        contentFrame._wnSectionFullH = 0
        contentFrame._wnVirtualContentHeight = nil
        return contentFrame
    end

    -- Leaf rows only are virtualized; headers/cards stay real.
    -- Row stripes (ApplyRowBackground index): still **per-section** 1..n â€” not one merged index across Favorites + Characters + Untracked.
    local function DrawCharactersIntoSection(contentFrame, list, isFavorite, listKey, emptyMessage)
        contentFrame._wnVirtualContentHeight = nil
        local sectionYOffset = 0
        if #list > 0 then
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            local VLM = ns.VirtualListModule
            local betweenRows = GetLayout().betweenRows or 0
            local stride = 46 + betweenRows
            local showReorder = currentSortKey == "manual"

            if mf and mf.scroll and contentFrame and VLM and VLM.SetupVirtualList then
                local n = #list
                local flatList = {}
                local rowY = 0
                for i = 1, n do
                    local char = list[i]
                    local charKey = GetCharKey(char)
                    -- VirtualList incremental reuse keys only on charKey; bust sig when keystone/gold/ilvl change.
                    local mk = char and char.mythicKey
                    local mkSig = (mk and tonumber(mk.level) and tonumber(mk.level) > 0)
                        and (tostring(mk.level) .. ":" .. tostring(mk.mapID or mk.dungeonID or ""))
                        or "0"
                    local rowSig = table.concat({
                        listKey or "section",
                        charKey or tostring(i),
                        "mk" .. mkSig,
                        "g" .. tostring(char and char.gold or 0),
                        "il" .. tostring(char and char.itemLevel or 0),
                    }, ":")
                    flatList[i] = {
                        type = "row",
                        yOffset = rowY,
                        height = stride,
                        xOffset = 0,
                        rowReuseSig = rowSig,
                        populateEntry = {
                            char = char,
                            index = i,
                            rowWidth = rowDrawWidth,
                            isFavorite = isFavorite,
                            showReorder = showReorder,
                            charList = list,
                            listKey = listKey,
                            positionInList = i,
                            totalInList = n,
                            currentPlayerKey = currentPlayerKey,
                        },
                    }
                    rowY = rowY + stride
                end

                local scrollChildForOff = (mf.scroll.GetScrollChild and mf.scroll:GetScrollChild()) or mf.scrollChild

                -- Offset remeasured every scroll paint (anchor walk); avoid stale GetTop snap at setup.
                local totalHeight = VLM.SetupVirtualList(mf, contentFrame, nil, flatList, {
                    createRowFn = function(container, _it, _idx)
                        return AcquireCharacterRow(container)
                    end,
                    populateRowFn = function(row, it, _idx)
                        local pe = it.populateEntry
                        local container = row:GetParent()
                        pcall(function()
                            WarbandNexus:DrawCharacterRow(container, pe.char, pe.index, pe.rowWidth, 0,
                                pe.isFavorite, pe.showReorder, pe.charList, pe.listKey,
                                pe.positionInList, pe.totalInList, pe.currentPlayerKey, row)
                        end)
                    end,
                    layoutRowFn = function(row, it, _idx)
                        local pe = it.populateEntry
                        if pe and pe.rowWidth then
                            ns.CharactersUI.ApplyCharacterRowInteriorLayout(row, pe.rowWidth)
                        end
                    end,
                    resizeLayoutOnly = true,
                    -- Required for resizeLayoutOnly to actually engage: without sig-based
                    -- reuse, frameReused is never true and every paint re-runs the full
                    -- DrawCharacterRow per visible row (rowReuseSig is set on each entry).
                    incrementalRowReuse = true,
                    fixedRowWidthFromEntry = true,
                    rowSpanContainerWidth = true,
                    rowPaintRightPad = 0,
                    releaseRowFn = ReleaseCharacterRow,
                })
                contentFrame._wnVirtualContentHeight = totalHeight
                sectionYOffset = totalHeight
                contentFrame:SetHeight(math.max(0.1, totalHeight))
                if scrollChildForOff and VLM.RefreshContainerTopOffsetCache then
                    VLM.RefreshContainerTopOffsetCache(contentFrame, scrollChildForOff, nil)
                end
            else
                local yAcc = 0
                for i = 1, #list do
                    local char = list[i]
                    local ok, nextYOffset = pcall(
                        self.DrawCharacterRow,
                        self,
                        contentFrame,
                        char,
                        i,
                        rowDrawWidth,
                        yAcc,
                        isFavorite,
                        showReorder,
                        list,
                        listKey,
                        i,
                        #list,
                        currentPlayerKey
                    )
                    if ok and nextYOffset then
                        yAcc = nextYOffset
                    else
                        yAcc = yAcc + (ROW_HEIGHT or 36)
                    end
                end
                sectionYOffset = yAcc
                contentFrame._wnSectionFullH = sectionYOffset
                if sectionYOffset > 0 then
                    contentFrame:SetHeight(sectionYOffset)
                else
                    contentFrame:SetHeight(0.1)
                end
            end
        elseif emptyMessage and emptyMessage ~= "" then
            local emptyText = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
            emptyText:SetPoint("TOP", contentFrame, "TOP", 0, -20)
            emptyText:SetText(ThemeTextHex("Muted") .. emptyMessage .. "|r")
            emptyText:SetWidth(math.max(200, (sectionStackW or width or 400) - 40))
            emptyText:SetJustifyH("CENTER")
            sectionYOffset = sectionYOffset + 50
            contentFrame:SetHeight(math.max(0.1, sectionYOffset))
        end

        contentFrame._wnSectionFullH = math.max(0.1, sectionYOffset)
        return sectionYOffset
    end

    local function AnchorSectionHeader(headerFrame)
        headerFrame:SetHeight(SECTION_H)
        if headerFrame.SetWidth then
            headerFrame:SetWidth(math.max(1, sectionStackW))
        end
        if isFirstSection then
            headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -yOffset)
            isFirstSection = false
        elseif previousSectionContent then
            headerFrame:SetPoint("TOPLEFT", previousSectionContent, "BOTTOMLEFT", 0, -SECTION_HEADER_GAP)
        else
            headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -yOffset)
        end
    end

    local drawFavorites = (sectionFilter == "all") or (sectionFilter == "favorites")
    local drawRegular = (sectionFilter == "all") or (sectionFilter == "regular")
    local drawUntracked = (sectionFilter == "untracked") or (sectionFilter == "all" and #untracked > 0)

    -- Section stack (when filter is "all"): Favorites -> user-defined custom headers (gold favorites first, then name/sort) -> Characters -> inactive last.

    -- Favorites
    if drawFavorites then
        local favoritesExpanded = self.db.profile.ui.favoritesExpanded
        local favoritesContent
        local favoritesVisualOpts = BuildCollapsibleSectionOpts({
            bodyGetter = function() return favoritesContent end,
            updateVisibleFn = CharactersVirtualScrollBump,
        }) or {
            animatedContent = function() return favoritesContent end,
        }
        favoritesVisualOpts.sectionPreset = "gold"
        favoritesVisualOpts.useFullParentWidth = true
        favoritesVisualOpts.sectionStackWidth = sectionStackW
        local favHeader, _, favIcon = CreateCollapsibleHeader(
            parent,
            ((ns.L and ns.L["HEADER_FAVORITES"]) or "Favorites"),
            "favorites",
            favoritesExpanded,
            function(isExpanded)
                self.db.profile.ui.favoritesExpanded = isExpanded
                if isExpanded then
                    if favoritesContent then
                        favoritesContent:Show()
                        favoritesContent:SetHeight(math.max(0.1, favoritesContent._wnSectionFullH or 0.1))
                    end
                elseif favoritesContent then
                    favoritesContent:Hide()
                    favoritesContent:SetHeight(0.1)
                end
            end,
            "GM-icon-assistActive-hover",
            true,
            nil,
            nil,
            favoritesVisualOpts
        )
        AnchorSectionHeader(favHeader)
        if favIcon then favIcon:SetSize(24, 24) end

        local favCount = FontManager:CreateFontString(favHeader, FontManager:GetFontRole("sectionHeaderCount"), "OVERLAY")
        favCount:SetPoint("RIGHT", favHeader, "RIGHT", -SECTION_HEADER_TEXT_INSET, 0)
        favCount:SetJustifyH("RIGHT")
        SetSectionHeaderCount(favCount, #trackedFavorites, "Normal")
        AttachSectionGoldTotal(favHeader, favCount, trackedFavorites)

        favoritesContent = AcquireSectionContentFrame(favHeader)
        local favoritesHeight = DrawCharactersIntoSection(
            favoritesContent,
            trackedFavorites,
            true,
            "favorites",
            (ns.L and ns.L["NO_FAVORITES"]) or "No favorite characters yet. Click the star icon to favorite a character."
        )
        if favoritesExpanded then
            favoritesContent:Show()
            favoritesContent:SetHeight(math.max(0.1, favoritesContent._wnSectionFullH or 0.1))
        else
            favoritesContent:Hide()
            favoritesContent:SetHeight(0.1)
        end
        previousSectionContent = favoritesContent
        yOffset = yOffset + SECTION_H + (favoritesExpanded and favoritesHeight or 0) + SECTION_HEADER_GAP
    end

    -- User-defined custom headers (any tracked character, favorites included)
    for cgi = 1, #customGroupsOrdered do
        local gMeta = customGroupsOrdered[cgi]
        local gid = gMeta.id
        local gList = groupedById[gid] or {}
        local gListKey = (ns.CharacterService and ns.CharacterService.GetCustomGroupListKey and ns.CharacterService:GetCustomGroupListKey(gid)) or ("group_" .. tostring(gid))
        -- "all": show every defined header (even empty) so users see where to assign; specific key: that section only.
        local showThisGroup = (sectionFilter == "all") or (sectionFilter == gListKey)
        if showThisGroup then
            if self.db.profile.characterGroupExpanded[gid] == nil then
                self.db.profile.characterGroupExpanded[gid] = true
            end
            local grpExpanded = self.db.profile.characterGroupExpanded[gid]
            local grpContent
            local isFavHeader = ns.CharacterService and ns.CharacterService.IsProfileCustomSectionHighlighted
                and ns.CharacterService:IsProfileCustomSectionHighlighted(self.db.profile, gid)
            local grpVisualOpts = BuildCollapsibleSectionOpts({
                bodyGetter = function() return grpContent end,
                updateVisibleFn = CharactersVirtualScrollBump,
            }) or { animatedContent = function() return grpContent end }
            grpVisualOpts.sectionPreset = isFavHeader and "gold" or "accent"
            grpVisualOpts.useFullParentWidth = true
            grpVisualOpts.sectionStackWidth = sectionStackW
            local grpTitle = gMeta.name or gid
            local grpHeaderAtlas = isFavHeader and "GM-icon-assistActive-hover" or "GM-icon-headCount"
            local grpHeader, grpExpandIcon, grpIcon, grpHeaderText = CreateCollapsibleHeader(
                parent,
                grpTitle,
                "cgrp_" .. tostring(gid),
                grpExpanded,
                function(isExpanded)
                    self.db.profile.characterGroupExpanded[gid] = isExpanded
                    if isExpanded then
                        if grpContent then
                            grpContent:Show()
                            grpContent:SetHeight(math.max(0.1, grpContent._wnSectionFullH or 0.1))
                        end
                    elseif grpContent then
                        grpContent:Hide()
                        grpContent:SetHeight(0.1)
                    end
                end,
                grpHeaderAtlas,
                true,
                nil,
                nil,
                grpVisualOpts
            )
            AnchorSectionHeader(grpHeader)
            if grpIcon then grpIcon:SetSize(24, 24) end

            -- Unified Custom Header chrome (count + [+] add button + gold star).
            -- Layout: [chevron] [icon] [gold-star] [title] ........ [add-btn] [count]
            if ns.UI_DecorateCustomHeader then
                ns.UI_DecorateCustomHeader(grpHeader, {
                    groupId = gid,
                    memberCount = #gList,
                    addon = WarbandNexus,
                    profile = self.db.profile,
                    expandIcon = grpExpandIcon,
                    iconFrame = grpIcon,
                    headerText = grpHeaderText,
                    includeAddButton = true,
                    addButtonRoster = characters,
                    refreshTab = nil,
                    goldTotal = (ns.CharacterService and ns.CharacterService.SumCharacterListGold)
                        and ns.CharacterService:SumCharacterListGold(gList) or nil,
                    -- Sections always render in array order now, so the arrows are always shown;
                    -- cgi is the section's real position and the ends grey out on their own.
                    showReorder = true,
                    sectionIndex = cgi,
                    sectionCount = #customGroupsOrdered,
                })
            end

            grpContent = AcquireSectionContentFrame(grpHeader)
            local grpHeight = DrawCharactersIntoSection(
                grpContent,
                gList,
                false,
                gListKey,
                (ns.L and ns.L["CUSTOM_HEADER_EMPTY"]) or "No characters in this header. Use the + button (next to Filter) or the row note icon to assign."
            )
            if grpExpanded then
                grpContent:Show()
                grpContent:SetHeight(math.max(0.1, grpContent._wnSectionFullH or 0.1))
            else
                grpContent:Hide()
                grpContent:SetHeight(0.1)
            end
            previousSectionContent = grpContent
            yOffset = yOffset + SECTION_H + (grpExpanded and grpHeight or 0) + SECTION_HEADER_GAP
        end
    end

    -- Regular characters (tracked, no custom section, not favorited)
    if drawRegular then
        local charactersExpanded = self.db.profile.ui.charactersExpanded
        local charactersContent
        local charVisualOpts = BuildCollapsibleSectionOpts({
            bodyGetter = function() return charactersContent end,
            updateVisibleFn = CharactersVirtualScrollBump,
        }) or {}
        charVisualOpts.sectionPreset = "accent"
        charVisualOpts.useFullParentWidth = true
        charVisualOpts.sectionStackWidth = sectionStackW
        local charHeader, _, charIcon = CreateCollapsibleHeader(
            parent,
            ((ns.L and ns.L["HEADER_CHARACTERS"]) or "Characters"),
            "characters",
            charactersExpanded,
            function(isExpanded)
                self.db.profile.ui.charactersExpanded = isExpanded
                if isExpanded then
                    if charactersContent then
                        charactersContent:Show()
                        charactersContent:SetHeight(math.max(0.1, charactersContent._wnSectionFullH or 0.1))
                    end
                elseif charactersContent then
                    charactersContent:Hide()
                    charactersContent:SetHeight(0.1)
                end
            end,
            "GM-icon-headCount",
            true,
            nil,
            nil,
            charVisualOpts
        )
        AnchorSectionHeader(charHeader)
        if charIcon then charIcon:SetSize(24, 24) end

        local charCount = FontManager:CreateFontString(charHeader, FontManager:GetFontRole("sectionHeaderCount"), "OVERLAY")
        charCount:SetPoint("RIGHT", charHeader, "RIGHT", -SECTION_HEADER_TEXT_INSET, 0)
        charCount:SetJustifyH("RIGHT")
        SetSectionHeaderCount(charCount, #trackedRegular, "Normal")
        AttachSectionGoldTotal(charHeader, charCount, trackedRegular)

        charactersContent = AcquireSectionContentFrame(charHeader)
        local charactersHeight = DrawCharactersIntoSection(
            charactersContent,
            trackedRegular,
            false,
            "regular",
            (ns.L and ns.L["ALL_FAVORITED"]) or "All characters are favorited!"
        )
        if charactersExpanded then
            charactersContent:Show()
            charactersContent:SetHeight(math.max(0.1, charactersContent._wnSectionFullH or 0.1))
        else
            charactersContent:Hide()
            charactersContent:SetHeight(0.1)
        end
        previousSectionContent = charactersContent
        yOffset = yOffset + SECTION_H + (charactersExpanded and charactersHeight or 0)
    end

    -- Untracked characters
    if drawUntracked then
        if not isFirstSection then
            yOffset = yOffset + SECTION_HEADER_GAP
        end
        if self.db.profile.ui.untrackedExpanded == nil then
            self.db.profile.ui.untrackedExpanded = false
        end

        local untrackedExpanded = self.db.profile.ui.untrackedExpanded
        local untrackedContent
        local untrackedVisualOpts = BuildCollapsibleSectionOpts({
            bodyGetter = function() return untrackedContent end,
            updateVisibleFn = CharactersVirtualScrollBump,
        }) or {
            animatedContent = function() return untrackedContent end,
        }
        untrackedVisualOpts.sectionPreset = "danger"
        untrackedVisualOpts.useFullParentWidth = true
        untrackedVisualOpts.sectionStackWidth = sectionStackW
        local untrackedHeader, _, untrackedIcon = CreateCollapsibleHeader(
            parent,
            ((ns.L and ns.L["UNTRACKED_CHARACTERS"]) or "Untracked Characters"),
            "untracked",
            untrackedExpanded,
            function(isExpanded)
                self.db.profile.ui.untrackedExpanded = isExpanded
                if isExpanded then
                    if untrackedContent then
                        untrackedContent:Show()
                        untrackedContent:SetHeight(math.max(0.1, untrackedContent._wnSectionFullH or 0.1))
                    end
                elseif untrackedContent then
                    untrackedContent:Hide()
                    untrackedContent:SetHeight(0.1)
                end
            end,
            "DungeonStoneCheckpointDeactivated",
            true,
            nil,
            nil,
            untrackedVisualOpts
        )
        AnchorSectionHeader(untrackedHeader)
        if untrackedIcon then untrackedIcon:SetSize(24, 24) end

        local untrackedCount = FontManager:CreateFontString(untrackedHeader, FontManager:GetFontRole("sectionHeaderCount"), "OVERLAY")
        untrackedCount:SetPoint("RIGHT", untrackedHeader, "RIGHT", -SECTION_HEADER_TEXT_INSET, 0)
        untrackedCount:SetJustifyH("RIGHT")
        SetSectionHeaderCount(untrackedCount, #untracked, "Muted")
        AttachSectionGoldTotal(untrackedHeader, untrackedCount, untracked)

        untrackedContent = AcquireSectionContentFrame(untrackedHeader)
        local untrackedHeight = DrawCharactersIntoSection(
            untrackedContent,
            untracked,
            false,
            "untracked",
            nil
        )
        if untrackedExpanded then
            untrackedContent:Show()
            untrackedContent:SetHeight(math.max(0.1, untrackedContent._wnSectionFullH or 0.1))
        else
            untrackedContent:Hide()
            untrackedContent:SetHeight(0.1)
        end
        previousSectionContent = untrackedContent
        yOffset = yOffset + SECTION_H + (untrackedExpanded and untrackedHeight or 0)
    end

    if ns.UI_SyncMainTabScrollChrome then
        ns.UI_SyncMainTabScrollChrome(mf, parent, yOffset)
    end

    if mf and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if mf.currentTab == "chars" then
                CharactersVirtualScrollBump()
            end
        end)
    end

    return yOffset
end

--- Section headers created by `CreateCollapsibleHeader` (stripe texture marker).
local function ForEachCharactersSectionHeader(scrollChild, fn)
    if not scrollChild or not fn or not scrollChild.GetNumChildren then return end
    local n = scrollChild:GetNumChildren() or 0
    for i = 1, n do
        local ch = select(i, scrollChild:GetChildren())
        if ch and ch._wnSectionStripe then
            fn(ch)
        end
    end
end

--- Walk scroll subtree for section virtual-list containers (`contentFrame._vlm_flatList`).
local function ForEachCharactersVirtualContainer(root, fn)
    if not root or type(fn) ~= "function" then return end
    if root._vlm_flatList and root._virtualUpdater then
        fn(root)
    end
    if not root.GetNumChildren then return end
    local n = root:GetNumChildren() or 0
    for i = 1, n do
        ForEachCharactersVirtualContainer(select(i, root:GetChildren()), fn)
    end
end

--- Resize: refresh section stack + virtual row widths without full tab rebuild when possible.
local function RelayoutCharactersSectionBodyWidths(scrollChild, viewportW, sideMargin)
    if not scrollChild or not viewportW or viewportW < 1 then return end
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local guildW = WarbandNexus and WarbandNexus._charListMaxGuildWidth
    local stackW
    if ns.UI_ResolveCharactersTabRowWidth then
        stackW = ns.UI_ResolveCharactersTabRowWidth(mf, scrollChild, metrics, guildW)
    else
        stackW = math.max(1, viewportW - (sideMargin or 12) * 2)
    end
    if (not stackW or stackW < 1) and viewportW then
        stackW = math.max(1, viewportW - (sideMargin or 12) * 2)
    end
    stackW = math.max(1, stackW or 1)
    scrollChild._charsSectionStackW = stackW
    if ns.CharactersUI.RelayoutCharactersColumnHeader then
        ns.CharactersUI.RelayoutCharactersColumnHeader(scrollChild, stackW)
    end
    ForEachCharactersSectionHeader(scrollChild, function(header)
        if header.SetWidth then
            header:SetWidth(stackW)
        end
    end)
    ForEachCharactersVirtualContainer(scrollChild, function(container)
        if container.SetWidth then
            container:SetWidth(stackW)
        end
    end)
end

local function ResolveCharactersTabRowPaintWidth(mf, scrollChild, contentWidth, metrics, forLiveResize)
    if forLiveResize and ns.UI_ResolveCharactersTabRowWidthForLive then
        local liveW = ns.UI_ResolveCharactersTabRowWidthForLive(mf, scrollChild, metrics, WarbandNexus._charListMaxGuildWidth)
        if liveW and liveW >= 1 then
            return liveW
        end
    end
    local addon = WarbandNexus
    local guildW = addon and addon._charListMaxGuildWidth
    local rowW
    if ns.UI_ResolveCharactersTabRowWidth then
        rowW = ns.UI_ResolveCharactersTabRowWidth(mf, scrollChild, metrics, guildW)
    else
        rowW = (ns.UI_ComputeCharactersMinScrollWidth and ns.UI_ComputeCharactersMinScrollWidth(addon, guildW))
            or contentWidth
            or (scrollChild and scrollChild:GetWidth())
            or 0
    end
    if rowW < 1 then
        rowW = 1100
    end
    return rowW
end

local function RefreshCharactersVirtualLayout(scrollChild, contentWidth)
    if not scrollChild then return false end
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local VLM = ns.VirtualListModule
    if not mf or not VLM then return false end
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local side = (metrics and metrics.sideMargin) or 12
    local viewportW = contentWidth
    if (not viewportW or viewportW < 1) and mf and ns.UI_GetMainTabViewportWidth then
        viewportW = ns.UI_GetMainTabViewportWidth(mf)
    end
    RelayoutCharactersSectionBodyWidths(scrollChild, viewportW, side)
    local rowW = ResolveCharactersTabRowPaintWidth(mf, scrollChild, contentWidth, metrics)
    if ns.UI_CloseCharacterTabFlyoutMenus then
        ns.UI_CloseCharacterTabFlyoutMenus()
    end
    if ns.UI_EnsureMainScrollLayout then
        ns.UI_EnsureMainScrollLayout()
    end
    local any = false
    ForEachCharactersVirtualContainer(scrollChild, function(container)
        local fl = container._vlm_flatList
        if fl then
            container._vlm_layoutTopOffset = nil
            for j = 1, #fl do
                local it = fl[j]
                if it and it.type == "row" and it.populateEntry then
                    it.populateEntry.rowWidth = rowW
                end
            end
            if VLM.RefreshVirtualListFlatList then
                VLM.RefreshVirtualListFlatList(mf, container, fl)
            elseif container._virtualUpdater then
                container._virtualUpdater()
            end
            any = true
        end
    end)
    CharactersVirtualScrollBump()
    if ns.UI_RefreshFixedHeaderChrome and mf then
        ns.UI_RefreshFixedHeaderChrome(mf)
    end
    if mf and mf.scrollChild and ns.UI_SyncMainTabScrollChrome then
        local bodyH = 0
        if scrollChild.GetHeight then
            bodyH = math.max(0, (scrollChild:GetHeight() or 0) - ((ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8))
        end
        ns.UI_SyncMainTabScrollChrome(mf, scrollChild, bodyH)
    end
    if mf and mf.scroll and ns.UI and ns.UI.Factory and ns.UI.Factory.UpdateHorizontalScrollBarVisibility then
        ns.UI.Factory:UpdateHorizontalScrollBarVisibility(mf.scroll)
    end
    return any
end


local function CharactersTabViewportRelayout(scrollChild, contentWidth, mf)
    if not mf or mf.currentTab ~= "chars" then return false end
    if ns.UI_IsMainFrameResizeSession and ns.UI_IsMainFrameResizeSession(mf) then
        return true
    end
    ns.CharactersUI.RelayoutCharactersGoldCards(scrollChild, contentWidth, mf)
    if RefreshCharactersVirtualLayout(scrollChild, contentWidth) then
        return true
    end
    return false
end

-- CharactersUI_*.lua satellites read this table (TOC: CharactersUI.lua before its satellites).
ns.CharactersUI._bind = {
    WarbandNexus = WarbandNexus,
    E = E,
    FontManager = FontManager,
    ShowTooltip = ShowTooltip,
    HideTooltip = HideTooltip,
    COLORS = COLORS,
    FormatMoney = FormatMoney,
    ThemeTextHex = ThemeTextHex,
    SemanticGoldHex = SemanticGoldHex,
    PresentFS = PresentFS,
    CreateCharacterDeleteDialogButton = CreateCharacterDeleteDialogButton,
    CreateIcon = CreateIcon,
    AcquireCharacterRow = AcquireCharacterRow,
    GetCharKey = GetCharKey,
    tinsert = tinsert,
    ResolveSessionCharactersTableKey = ResolveSessionCharactersTableKey,
    IsCharLoggedInSession = IsCharLoggedInSession,
    GetLayout = GetLayout,
    BuildGuildText = BuildGuildText,
}

if ns.UI_LayoutCoordinator then
    ns.UI_LayoutCoordinator:RegisterTabAdapter("chars", {
        OnViewportWidthChanged = CharactersTabViewportRelayout,
        OnViewportLayoutCommit = function(scrollChild, contentWidth, mf)
            if not mf or mf.currentTab ~= "chars" then return false end
            mf._wnCharsLiveRelayoutW = nil
            -- Single full redraw after corner-drag (gold mode, section offsets, columns, gradient).
            return false
        end,
    })
end
