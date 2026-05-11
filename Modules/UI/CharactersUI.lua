--[[
    Warband Nexus - Characters Tab
    Display all tracked characters with gold, level, and last seen info
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager  -- Centralized font management

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

local DebugPrint = ns.DebugPrint

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Import shared UI components (always get fresh reference)
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local FormatMoney = ns.UI_FormatMoney
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local BuildAccordionVisualOpts = ns.UI_BuildAccordionVisualOpts
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateFactionIcon = ns.UI_CreateFactionIcon
local CreateRaceIcon = ns.UI_CreateRaceIcon
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local CreateClassIcon = ns.UI_CreateClassIcon
local CreateFavoriteButton = ns.UI_CreateFavoriteButton
local CreateOnlineIndicator = ns.UI_CreateOnlineIndicator
local GetColumnOffset = ns.UI_GetColumnOffset
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateIcon = ns.UI_CreateIcon -- Factory for icons
local FormatNumber = ns.UI_FormatNumber
-- Pooling constants
local AcquireCharacterRow = ns.UI_AcquireCharacterRow
local ReleaseCharacterRow = ns.UI_ReleaseCharacterRow

--- Virtual-scroll tabs: refresh row culling after accordion tweens / layout (ReputationUI parity).
local function CharactersVirtualScrollBump()
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mf and mf._virtualScrollUpdate then
        mf._virtualScrollUpdate()
    end
end

local CHAR_ROW_COLUMNS = ns.UI_CHAR_ROW_COLUMNS

local GetCharKey = ns.UI_GetCharKey
local tinsert = table.insert
local tremove = table.remove

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
    local raw = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not raw then return false end
    if rowKey == raw then return true end
    local resolved = ResolveSessionCharactersTableKey()
    if resolved and rowKey == resolved then return true end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local a = ns.Utilities:GetCanonicalCharacterKey(rowKey)
        local b = ns.Utilities:GetCanonicalCharacterKey(raw)
        if a and b and a == b then return true end
    end
    return false
end

--- True if a stored order key string refers to the logged-in session (manual sort / pin-to-top).
local function OrderKeyIsSessionChar(orderKey)
    if not orderKey then return false end
    local raw = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not raw then return false end
    if orderKey == raw then return true end
    local resolved = ResolveSessionCharactersTableKey()
    if resolved and orderKey == resolved then return true end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local a = ns.Utilities:GetCanonicalCharacterKey(orderKey)
        local b = ns.Utilities:GetCanonicalCharacterKey(raw)
        if a and b and a == b then return true end
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
local SECONDARY_PROF_KEYS = { "cooking" }

local function BuildGuildText(char, isCurrentCharacter)
    local guildName = (char and char.guildName) or nil
    if isCurrentCharacter then
        local liveGuild = IsInGuild() and GetGuildInfo("player") or nil
        if liveGuild and not (issecretvalue and issecretvalue(liveGuild)) then
            guildName = liveGuild
        end
    end

    if guildName and not (issecretvalue and issecretvalue(guildName)) and guildName ~= "" then
        -- Guild name: soft lavender so it’s visible but not louder than name
        return string.format("|cffffffff%s|r", guildName)
    end

    return "|cff5c5c5c—|r"
end

---Pending-mail badge next to character name. Inline |T paths are unreliable in modern clients; use a Texture.
local function ApplyPendingMailIconTexture(tex)
    tex:SetTexCoord(0, 1, 0, 1)
    if C_Texture and C_Texture.GetAtlasInfo then
        local atlasTry = { "Mail-Icon", "minimap-tracking-mailbox", "Mailbox-Tracking" }
        for i = 1, #atlasTry do
            local name = atlasTry[i]
            local ok, info = pcall(C_Texture.GetAtlasInfo, name)
            if ok and info then
                tex:SetAtlas(name)
                return
            end
        end
    end
    if C_Texture and C_Texture.GetFileIDFromPath then
        local paths = { "interface/minimap/tracking/mailbox", "Interface/Minimap/Tracking/Mailbox" }
        for i = 1, #paths do
            local p = paths[i]
            local ok, fid = pcall(C_Texture.GetFileIDFromPath, p)
            if ok and fid and type(fid) == "number" and fid > 0 then
                tex:SetTexture(fid)
                return
            end
        end
    end
    tex:SetTexture("Interface/Minimap/Tracking/Mailbox")
end

--============================================================================
-- EVENT-DRIVEN UI REFRESH
--============================================================================

---Register event listener for character updates
---@param parent Frame Parent frame for event registration
local function RegisterCharacterEvents(parent)
    -- Register only once per parent
    if parent.characterUpdateHandler then
        return
    end
    parent.characterUpdateHandler = true
    
    -- WN_CHARACTER_UPDATED: REMOVED — UI.lua's SchedulePopulateContent already handles
    -- chars tab refresh via PopulateContent → DrawCharacterList. Having both caused double rebuild.
    
    -- WN_CHARACTER_TRACKING_CHANGED refresh is centralized in UI.lua.
end

--- Accordion defaults for Favorites / Characters / Untracked (nil handling matches PopulateContent).
local function CharactersUISectionExpandedTriplet(ui)
    ui = ui or {}
    local fav = ui.favoritesExpanded
    if fav == nil then fav = true end
    local ch = ui.charactersExpanded
    if ch == nil then ch = true end
    local unt = ui.untrackedExpanded
    if unt == nil then unt = false end
    return fav, ch, unt
end

local function CharactersUISectionAllExpanded(ui)
    local fav, ch, unt = CharactersUISectionExpandedTriplet(ui)
    if not (fav and ch and unt) then return false end
    local profile = WarbandNexus.db and WarbandNexus.db.profile
    if not profile then return true end
    local groups = profile.characterCustomGroups or {}
    local ge = profile.characterGroupExpanded or {}
    for gi = 1, #groups do
        local gid = groups[gi].id
        if ge[gid] == false then
            return false
        end
    end
    return true
end

--============================================================================
-- DRAW CHARACTER LIST
--============================================================================

function WarbandNexus:DrawCharacterList(parent)
    -- Request updated WoW Token market price (async; result used by Total Gold card)
    if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice then
        C_WowTokenPublic.UpdateMarketPrice()
    end

    local width = parent:GetWidth() - 20

    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = 8
    
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
        ns.VirtualListModule.ClearVirtualScroll(mfForVirtual)
    end

    -- Nested character rows: PopulateContent walks subtrees via UI_ReleaseCharacterRowsFromSubtree before recycle.
    
    local currentPlayerKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    local sessionTableKey = ResolveSessionCharactersTableKey() or currentPlayerKey
    if self.db.global.characters and sessionTableKey and self.db.global.characters[sessionTableKey] then
        self.db.global.characters[sessionTableKey].lastSeen = time()
    end
    
    local characters = self:GetAllCharacters()

    -- ===== TITLE CARD (in fixedHeader - non-scrolling) — shared Characters-tab layout =====
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local CHAR_TITLE_RIGHT_RESERVE = 256
    local subtitleLine = (ns.L and ns.L["CHARACTERS_SUBTITLE"])
        or "A scrollable list of your characters with gold, level, gear, and key stats in one place."
    local titleCard, headerIcon, titleTextContainer, titleText, subtitleText = ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "characters",
        titleText = "|cff" .. hexColor .. ((ns.L and ns.L["YOUR_CHARACTERS"]) or "Your Characters") .. "|r",
        subtitleText = subtitleLine,
        textRightInset = CHAR_TITLE_RIGHT_RESERVE,
    })
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)

    local titleControlInset = GetLayout().TITLE_CARD_CONTROL_RIGHT_INSET or 20

    -- Sort dropdown anchors at card top-right; expand/collapse sit to its left (no overlap).
    local sortAnchorFrame = titleCard
    local sortAnchorPoint = "RIGHT"
    local sortAnchorX = -titleControlInset

    if ns.UI_CreateCharacterTabAdvancedFilterButton then
        if ns.CharacterService and ns.CharacterService.EnsureCustomCharacterSectionsProfile then
            ns.CharacterService:EnsureCustomCharacterSectionsProfile(self.db.profile)
        end
        local sortOptions = {
            {key = "default", label = (ns.L and ns.L["SORT_MODE_DEFAULT"]) or "Default Order"},
            {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
            {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
            {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
            {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
            {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
            {key = "realm", label = (ns.L and ns.L["SORT_MODE_REALM"]) or "Realm (A-Z)"},
        }
        if not self.db.profile.characterSort then self.db.profile.characterSort = {} end
        if not self.db.profile.characterSectionFilter then self.db.profile.characterSectionFilter = { sectionKey = "all" } end
        local sortBtn = ns.UI_CreateCharacterTabAdvancedFilterButton(titleCard, {
            sortOptions = sortOptions,
            dbSortTable = self.db.profile.characterSort,
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
            sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleControlInset, 0)
            sortBtn:SetFrameLevel(titleCard:GetFrameLevel() + 5)
            -- Match Filter row height (Factory advanced filter uses BUTTON_HEIGHT).
            local sectionToolbarBtnSize = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
            -- Visible entry for custom sections: same footprint as Filter, left of it.
            local secQuick = titleCard._wnCharCustomSectionBtn
            if not secQuick and ns.UI and ns.UI.Factory and ns.UI.Factory.CreateButton then
                secQuick = ns.UI.Factory:CreateButton(titleCard, sectionToolbarBtnSize, sectionToolbarBtnSize, false)
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
                titleCard._wnCharCustomSectionBtn:ClearAllPoints()
                titleCard._wnCharCustomSectionBtn:SetPoint("RIGHT", sortBtn, "LEFT", -8, 0)
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
        local sortOptions = {
            {key = "default", label = (ns.L and ns.L["SORT_MODE_DEFAULT"]) or "Default Order"},
            {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
            {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
            {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
            {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
            {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
            {key = "realm", label = (ns.L and ns.L["SORT_MODE_REALM"]) or "Realm (A-Z)"},
        }
        if not self.db.profile.characterSort then self.db.profile.characterSort = {} end
        local sortBtn = ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.characterSort, function()
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end)
        sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleControlInset, 0)
        sortBtn:SetFrameLevel(titleCard:GetFrameLevel() + 5)
        sortAnchorFrame = sortBtn
        sortAnchorPoint = "LEFT"
        sortAnchorX = -10
    end

    -- Single toolbar toggle: shared helper (same shell as Storage/Currency/Reputation title toggles).
    if ns.UI_CreateOrAcquireTitleToolbarExpandCollapseToggle and ns.UI_ApplyTitleToolbarExpandCollapseToggleAtlas then
        local ownerFrame = parent
        local toggleBtn = ns.UI_CreateOrAcquireTitleToolbarExpandCollapseToggle(ownerFrame, titleCard)
        if toggleBtn then
            local function charSectionCollapseMode()
                return CharactersUISectionAllExpanded(WarbandNexus.db.profile.ui or {})
            end
            toggleBtn:ClearAllPoints()
            toggleBtn:SetPoint("RIGHT", sortAnchorFrame, sortAnchorPoint, sortAnchorX, 0)
            ns.UI_ApplyTitleToolbarExpandCollapseToggleAtlas(toggleBtn, charSectionCollapseMode)
            toggleBtn:SetScript("OnEnter", function(btnFrame)
                GameTooltip:SetOwner(btnFrame, "ANCHOR_BOTTOMRIGHT")
                local collapseMode = charSectionCollapseMode()
                local tipKey = collapseMode and "CHARACTERS_SECTION_TOGGLE_COLLAPSE_TOOLTIP" or "CHARACTERS_SECTION_TOGGLE_EXPAND_TOOLTIP"
                local fb = collapseMode
                    and "Collapse Favorites, Characters, and Untracked sections."
                    or "Expand Favorites, Characters, and Untracked sections."
                GameTooltip:SetText((ns.L and ns.L[tipKey]) or fb, 1, 1, 1)
                GameTooltip:Show()
            end)
            toggleBtn:SetScript("OnLeave", GameTooltip_Hide)
            toggleBtn:SetScript("OnClick", function()
                if not WarbandNexus.db.profile.ui then WarbandNexus.db.profile.ui = {} end
                local ui = WarbandNexus.db.profile.ui
                if CharactersUISectionAllExpanded(ui) then
                    ui.favoritesExpanded = false
                    ui.charactersExpanded = false
                    ui.untrackedExpanded = false
                    if not WarbandNexus.db.profile.characterGroupExpanded then WarbandNexus.db.profile.characterGroupExpanded = {} end
                    local cg = WarbandNexus.db.profile.characterCustomGroups or {}
                    for ei = 1, #cg do
                        WarbandNexus.db.profile.characterGroupExpanded[cg[ei].id] = false
                    end
                else
                    ui.favoritesExpanded = true
                    ui.charactersExpanded = true
                    ui.untrackedExpanded = true
                    if not WarbandNexus.db.profile.characterGroupExpanded then WarbandNexus.db.profile.characterGroupExpanded = {} end
                    local cg2 = WarbandNexus.db.profile.characterCustomGroups or {}
                    for ei = 1, #cg2 do
                        WarbandNexus.db.profile.characterGroupExpanded[cg2[ei].id] = true
                    end
                end
                ns.UI_ApplyTitleToolbarExpandCollapseToggleAtlas(toggleBtn, charSectionCollapseMode)
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
            end)
            toggleBtn:Show()
        end
    end
    
    -- NO TRACKING: Static text, never overflows
    
    titleCard:Show()
    headerYOffset = headerYOffset + 75

    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    local yOffset = 8

    -- ===== TOTAL GOLD DISPLAY =====
    -- Get current character's gold (only if tracked)
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
    local currentCharGold = 0
    local isLoadingCharacterData = false
    
    -- Check if character data is being loaded (SaveCharacter in progress)
    if isTracked then
        currentCharGold = ns.Utilities:GetLiveCharacterMoneyCopper(0)

        -- Check if character exists in DB (if not, data is being collected)
        local dbKey = sessionTableKey or currentPlayerKey
        if not dbKey or not self.db.global.characters[dbKey] then
            isLoadingCharacterData = true
        elseif not self.db.global.characters[dbKey].gold then
            -- Character exists but gold not saved yet (initial scan)
            -- Note: DB stores gold/silver/copper separately, not totalCopper
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
    
    -- Calculate card width for 3 cards in a row (same as Statistics)
    local leftMargin = SIDE_MARGIN
    local rightMargin = SIDE_MARGIN
    local cardSpacing = 10
    local totalSpacing = cardSpacing * 2  -- 2 gaps between 3 cards
    local threeCardWidth = (width - leftMargin - rightMargin - totalSpacing) / 3
    local card3Width = width - leftMargin - rightMargin - 2 * threeCardWidth - 2 * cardSpacing
    -- Side-by-side Total Gold + Token needs ~460px+ on the third card; below that, stack vertically
    local GOLD_TOKEN_MIN_SPLIT_WIDTH = 460
    local stackGoldToken = card3Width < GOLD_TOKEN_MIN_SPLIT_WIDTH
    local goldRowHeight = stackGoldToken and 108 or 90
    
    -- Characters Gold Card (Left)
    local charGoldCard = CreateCard(parent, goldRowHeight)
    charGoldCard:SetWidth(threeCardWidth)
    charGoldCard:SetPoint("TOPLEFT", leftMargin, -yOffset)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        ApplyVisuals(charGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Current Character icon (same as Characters header)
    -- Use factory for standardized card header layout
    local CreateCardHeaderLayout = ns.UI_CreateCardHeaderLayout
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
    
    local goldDisplayText = isLoadingCharacterData and "|cff888888" .. ((ns.L and ns.L["LOADING"]) or "Loading...") .. "|r" or FormatMoney(currentCharGold, 14)
    
    local cg1Layout = CreateCardHeaderLayout(
        charGoldCard,
        GetCharacterSpecificIcon(),
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
    else
        -- Cleanup spinner if data loaded
        charGoldCard:SetScript("OnUpdate", nil)
        if charGoldCard.loadingSpinner then
            charGoldCard.loadingSpinner:Hide()
        end
    end
    
    -- NO TRACKING: Numbers rarely overflow (formatted gold)
    
    -- Warband Gold Card (Middle)
    local wbGoldCard = CreateCard(parent, goldRowHeight)
    wbGoldCard:SetWidth(threeCardWidth)
    wbGoldCard:SetPoint("LEFT", charGoldCard, "RIGHT", cardSpacing, 0)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        ApplyVisuals(wbGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
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
    
    -- Total Gold + Token Card (Right — wider card spanning remaining space)
    local totalGoldCard = CreateCard(parent, goldRowHeight)
    totalGoldCard:SetPoint("LEFT", wbGoldCard, "RIGHT", cardSpacing, 0)
    totalGoldCard:SetPoint("RIGHT", -rightMargin, 0)

    -- Apply visuals with accent border
    if ApplyVisuals then
        ApplyVisuals(totalGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end

    -- Vertical divider (hidden when Total Gold + Token are stacked)
    local divider = totalGoldCard:CreateTexture(nil, "ARTWORK")
    divider:SetSize(1, 50)
    divider:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4)

    -- Left block: Total Gold (icon + label + value)
    local tgIcon = CreateIcon(totalGoldCard, "BonusLoot-Chest", 36, true, nil, true)
    tgIcon:Show()

    local tgTextContainer = CreateFrame("Frame", nil, totalGoldCard)

    local tgLabel = FontManager:CreateFontString(tgTextContainer, "subtitle", "OVERLAY")
    tgLabel:SetText((ns.L and ns.L["HEADER_TOTAL_GOLD"]) or "TOTAL GOLD")
    tgLabel:SetTextColor(1, 1, 1)
    tgLabel:SetJustifyH("LEFT")
    tgLabel:SetPoint("BOTTOM", tgTextContainer, "CENTER", 0, 0)
    tgLabel:SetPoint("LEFT", tgTextContainer, "LEFT", 0, 0)

    local tgValue = FontManager:CreateFontString(tgTextContainer, "body", "OVERLAY")
    tgValue:SetText(FormatMoney(totalWithWarband, 14))
    tgValue:SetJustifyH("LEFT")
    tgValue:SetPoint("TOP", tgTextContainer, "CENTER", 0, -4)
    tgValue:SetPoint("LEFT", tgTextContainer, "LEFT", 0, 0)
    tgValue:SetNonSpaceWrap(false)

    -- Right block: WoW Token (icon + label + price with token count)
    -- GetCurrentMarketPrice updates asynchronously after UpdateMarketPrice(); TOKEN_MARKET_PRICE_UPDATED refreshes the tab (Core.lua).
    local tokenPrice = C_WowTokenPublic and C_WowTokenPublic.GetCurrentMarketPrice and select(1, C_WowTokenPublic.GetCurrentMarketPrice())

    local tkIcon = totalGoldCard:CreateTexture(nil, "ARTWORK")
    tkIcon:SetSize(28, 28)
    tkIcon:SetTexture("Interface\\Icons\\WoW_Token01")
    tkIcon:Show()

    local tkTextContainer = CreateFrame("Frame", nil, totalGoldCard)

    local tkLabel = FontManager:CreateFontString(tkTextContainer, "subtitle", "OVERLAY")
    tkLabel:SetText((ns.L and ns.L["WOW_TOKEN_LABEL"]) or "WOW TOKEN")
    tkLabel:SetTextColor(1, 1, 1)
    tkLabel:SetJustifyH("LEFT")
    tkLabel:SetPoint("BOTTOM", tkTextContainer, "CENTER", 0, 0)
    tkLabel:SetPoint("LEFT", tkTextContainer, "LEFT", 0, 0)

    local tkValue = FontManager:CreateFontString(tkTextContainer, "body", "OVERLAY")
    tkValue:SetJustifyH("LEFT")
    tkValue:SetPoint("TOP", tkTextContainer, "CENTER", 0, -4)
    tkValue:SetPoint("LEFT", tkTextContainer, "LEFT", 0, 0)
    tkValue:SetNonSpaceWrap(false)

    if stackGoldToken then
        divider:Hide()
        tgIcon:SetPoint("TOPLEFT", totalGoldCard, "TOPLEFT", 12, -12)
        tgTextContainer:ClearAllPoints()
        tgTextContainer:SetPoint("TOP", totalGoldCard, "TOP", 0, -10)
        tgTextContainer:SetPoint("LEFT", tgIcon, "RIGHT", 10, 0)
        tgTextContainer:SetPoint("RIGHT", totalGoldCard, "RIGHT", -10, 0)
        tgTextContainer:SetHeight(40)

        local midRule = totalGoldCard:CreateTexture(nil, "ARTWORK")
        midRule:SetHeight(1)
        midRule:SetPoint("LEFT", totalGoldCard, "LEFT", 10, 0)
        midRule:SetPoint("RIGHT", totalGoldCard, "RIGHT", -10, 0)
        midRule:SetPoint("TOP", totalGoldCard, "TOP", 0, -52)
        midRule:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.35)

        tkIcon:SetPoint("TOPLEFT", totalGoldCard, "TOPLEFT", 14, -58)
        tkTextContainer:ClearAllPoints()
        tkTextContainer:SetPoint("TOP", totalGoldCard, "TOP", 0, -56)
        tkTextContainer:SetPoint("LEFT", tkIcon, "RIGHT", 10, 0)
        tkTextContainer:SetPoint("RIGHT", totalGoldCard, "RIGHT", -10, 0)
        tkTextContainer:SetHeight(40)
    else
        divider:Show()
        divider:SetPoint("CENTER", totalGoldCard, "CENTER", 0, 0)
        tgIcon:SetPoint("CENTER", totalGoldCard, "LEFT", 15 + 18, 0)
        tgTextContainer:ClearAllPoints()
        tgTextContainer:SetPoint("LEFT", tgIcon, "RIGHT", 12, 0)
        tgTextContainer:SetPoint("RIGHT", divider, "LEFT", -8, 0)
        tgTextContainer:SetPoint("TOP", tgIcon, "TOP", 0, 0)
        tgTextContainer:SetPoint("BOTTOM", tgIcon, "BOTTOM", 0, 0)

        tkIcon:SetPoint("LEFT", divider, "RIGHT", 14, 0)
        tkTextContainer:ClearAllPoints()
        tkTextContainer:SetPoint("LEFT", tkIcon, "RIGHT", 10, 0)
        tkTextContainer:SetPoint("RIGHT", totalGoldCard, "RIGHT", -12, 0)
        tkTextContainer:SetPoint("TOP", tkIcon, "TOP", 0, 0)
        tkTextContainer:SetPoint("BOTTOM", tkIcon, "BOTTOM", 0, 0)
    end

    if tokenPrice and tokenPrice > 0 then
        local affordableCount = math.floor(totalWithWarband / tokenPrice)
        tkValue:SetText(
            FormatMoney(tokenPrice, 12)
                .. "  |cff66c0ff("
                .. affordableCount
                .. " "
                .. (((ns.L and ns.L["WOW_TOKEN_COUNT_LABEL"]) or "Tokens"))
                .. ")|r"
        )
    else
        tkValue:SetText("|cff888888" .. ((ns.L and ns.L["NOT_AVAILABLE_SHORT"]) or "N/A") .. "|r")
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

    yOffset = yOffset + (stackGoldToken and 118 or 100)
    
    local sortOptions = {
        {key = "default", label = (ns.L and ns.L["SORT_MODE_DEFAULT"]) or "Default Order"},
        {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
        {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
        {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
        {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
        {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
        {key = "realm", label = (ns.L and ns.L["SORT_MODE_REALM"]) or "Realm (A-Z)"},
    }
    
    if not self.db.profile.characterSort then self.db.profile.characterSort = {} end
    local sk = self.db.profile.characterSort.key
    local currentSortKey = (type(sk) == "string" and sk ~= "" and
        (sk == "default" or sk == "manual" or sk == "name" or sk == "level" or sk == "ilvl" or sk == "gold" or sk == "realm"))
        and sk or "default"

    local sectionFilter = "all"
    if self.db.profile.characterSectionFilter and type(self.db.profile.characterSectionFilter.sectionKey) == "string" then
        sectionFilter = self.db.profile.characterSectionFilter.sectionKey
    end
    if ns.CharacterService and ns.CharacterService.EnsureCustomCharacterSectionsProfile then
        ns.CharacterService:EnsureCustomCharacterSectionsProfile(self.db.profile)
    end

    local favoriteKeySet = (ns.CharacterService and ns.CharacterService.BuildFavoriteKeySet)
        and ns.CharacterService:BuildFavoriteKeySet(self) or {}
    
    -- ===== SORT CHARACTERS: FAVORITES -> REGULAR =====
    local trackedFavorites = {}
    local trackedRegular = {}
    local untracked = {}
    
    for i = 1, #characters do
        local char = characters[i]
        local charKey = GetCharKey(char)
        local isTracked = char.isTracked ~= false  -- Default to true if not set
        
        -- Separate by tracking status first, then favorites
        if not isTracked then
            tinsert(untracked, char)
        elseif ns.CharacterService then
            local isFav = (ns.CharacterService.IsFavoriteFromKeySet and ns.CharacterService:IsFavoriteFromKeySet(favoriteKeySet, charKey))
                or ns.CharacterService:IsFavoriteCharacter(self, charKey)
            if isFav then
                tinsert(trackedFavorites, char)
            else
                tinsert(trackedRegular, char)
            end
        end
    end

    -- Split non-favorites into custom header buckets + ungrouped (must run after trackedRegular is built).
    local customGroupsOrdered = (ns.CharacterService and ns.CharacterService.BuildOrderedCustomCharacterGroups)
        and ns.CharacterService:BuildOrderedCustomCharacterGroups(self.db.profile, currentSortKey)
        or (self.db.profile.characterCustomGroups or {})
    local assignments = self.db.profile.characterGroupAssignments or {}
    local groupedById = {}
    for gi = 1, #customGroupsOrdered do
        groupedById[customGroupsOrdered[gi].id] = {}
    end
    local trackedRegularUngrouped = {}
    for ri = 1, #trackedRegular do
        local char = trackedRegular[ri]
        local ck = GetCharKey(char)
        local gid = nil
        if ck and ns.CharacterService and ns.CharacterService.GetCharacterCustomSectionId then
            gid = ns.CharacterService:GetCharacterCustomSectionId(self, ck)
        elseif ck then
            gid = assignments[ck]
        end
        if gid and groupedById[gid] then
            tinsert(groupedById[gid], char)
        else
            tinsert(trackedRegularUngrouped, char)
        end
    end
    trackedRegular = trackedRegularUngrouped
    
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
        local sortMode = currentSortKey

        if sortMode ~= "manual" then
            if sortMode == "default" then
                -- Standard: logged-in character first, then level (high to low), then name (A-Z, case-insensitive).
                table.sort(list, function(a, b)
                    local aOn = IsCharLoggedInSession(a)
                    local bOn = IsCharLoggedInSession(b)
                    if aOn ~= bOn then
                        return aOn
                    end
                    if (a.level or 0) ~= (b.level or 0) then
                        return (a.level or 0) > (b.level or 0)
                    end
                    return CompareCharNameLower(a, b)
                end)
                return list
            end
            table.sort(list, function(a, b)
                if sortMode == "name" then
                    return CompareCharNameLower(a, b)
                elseif sortMode == "level" then
                    if (a.level or 0) ~= (b.level or 0) then
                        return (a.level or 0) > (b.level or 0)
                    else
                        return CompareCharNameLower(a, b)
                    end
                elseif sortMode == "ilvl" then
                    if (a.itemLevel or 0) ~= (b.itemLevel or 0) then
                        return (a.itemLevel or 0) > (b.itemLevel or 0)
                    else
                        return CompareCharNameLower(a, b)
                    end
                elseif sortMode == "gold" then
                    local goldA = ns.Utilities:GetCharTotalCopper(a)
                    local goldB = ns.Utilities:GetCharTotalCopper(b)
                    if goldA ~= goldB then
                        return goldA > goldB
                    else
                        return CompareCharNameLower(a, b)
                    end
                elseif sortMode == "realm" then
                    local ra = SafeLower(a.realm or "")
                    local rb = SafeLower(b.realm or "")
                    if ra ~= rb then
                        return ra < rb
                    else
                        return CompareCharNameLower(a, b)
                    end
                end
                -- Fallback
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return CompareCharNameLower(a, b)
                end
            end)
            return list
        end
        
        local customOrder = self.db.profile.characterOrder[orderKey] or {}
        
        -- If custom order exists and has items, use it
        if #customOrder > 0 then
            local ordered = {}
            local charMap = {}
            
            -- Create a map for quick lookup
            for i = 1, #list do
                local char = list[i]
                local key = GetCharKey(char)
                charMap[key] = char
            end
            
            -- Add characters in custom order
            for i = 1, #customOrder do
                local charKey = customOrder[i]
                if charMap[charKey] then
                    tinsert(ordered, charMap[charKey])
                    charMap[charKey] = nil  -- Remove to track remaining
                end
            end
            
            -- Add any new characters not in custom order (at the end, sorted)
            local remaining = {}
            for _, char in pairs(charMap) do
                tinsert(remaining, char)
            end
            table.sort(remaining, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return CompareCharNameLower(a, b)
                end
            end)
            for i = 1, #remaining do
                local char = remaining[i]
                tinsert(ordered, char)
            end
            
            return ordered
        else
            -- Default sort: level desc â†’ name asc (ignore table header sorting for now)
            table.sort(list, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return CompareCharNameLower(a, b)
                end
            end)
            return list
        end
    end
    
    -- Sort favorites, each custom header bucket, ungrouped regular, then untracked
    trackedFavorites = sortCharacters(trackedFavorites, "favorites")
    for gi = 1, #customGroupsOrdered do
        local gid = customGroupsOrdered[gi].id
        local list = groupedById[gid]
        if list then
            local lk = (ns.CharacterService and ns.CharacterService.GetCustomGroupListKey and ns.CharacterService:GetCustomGroupListKey(gid)) or ("group_" .. tostring(gid))
            sortCharacters(list, lk)
        end
    end
    trackedRegular = sortCharacters(trackedRegular, "regular")
    untracked = sortCharacters(untracked, "untracked")

    -- Logged-in character always first within each section (any sort mode / manual custom order).
    local function pinOnlineCharacterFirst(list)
        if not list or #list == 0 then return end
        for i = 1, #list do
            if IsCharLoggedInSession(list[i]) then
                if i > 1 then
                    local c = tremove(list, i)
                    tinsert(list, 1, c)
                end
                break
            end
        end
    end
    pinOnlineCharacterFirst(trackedFavorites)
    for gi = 1, #customGroupsOrdered do
        local gid = customGroupsOrdered[gi].id
        if groupedById[gid] then pinOnlineCharacterFirst(groupedById[gid]) end
    end
    pinOnlineCharacterFirst(trackedRegular)
    pinOnlineCharacterFirst(untracked)
    
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
    
    -- ===== EMPTY STATE =====
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
    
    -- ===== COLLAPSIBLE CHARACTER SECTIONS (accordion animated) =====
    local SECTION_H = (GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT) or 36
    local SECTION_HEADER_GAP = 12
    local previousSectionContent = nil
    local isFirstSection = true

    local function AcquireSectionContentFrame(anchorHeader)
        local contentFrame = nil
        if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateContainer then
            contentFrame = ns.UI.Factory:CreateContainer(parent, math.max(1, parent:GetWidth()), 1, false)
        else
            contentFrame = CreateFrame("Frame", nil, parent)
            contentFrame:SetSize(math.max(1, parent:GetWidth()), 1)
        end

        contentFrame:ClearAllPoints()
        contentFrame:SetPoint("TOPLEFT", anchorHeader, "BOTTOMLEFT", -SIDE_MARGIN, 0)
        contentFrame:SetPoint("TOPRIGHT", anchorHeader, "BOTTOMRIGHT", SIDE_MARGIN, 0)
        contentFrame:SetHeight(0.1)
        contentFrame._wnAccordionFullH = 0
        contentFrame._wnVirtualContentHeight = nil
        return contentFrame
    end

    -- Leaf rows only are virtualized; headers/cards stay real.
    -- Row stripes (ApplyRowBackground index): still **per-section** 1..n — not one merged index across Favorites + Characters + Untracked.
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
                local flatList = {}
                local rowY = 0
                for i = 1, #list do
                    flatList[#flatList + 1] = {
                        type = "row",
                        yOffset = rowY,
                        height = stride,
                        xOffset = SIDE_MARGIN,
                        populateEntry = {
                            char = list[i],
                            index = i,
                            rowWidth = width,
                            isFavorite = isFavorite,
                            showReorder = showReorder,
                            charList = list,
                            listKey = listKey,
                            positionInList = i,
                            totalInList = #list,
                            currentPlayerKey = currentPlayerKey,
                        },
                    }
                    rowY = rowY + stride
                end

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
                    releaseRowFn = ReleaseCharacterRow,
                })
                contentFrame._wnVirtualContentHeight = totalHeight
                sectionYOffset = totalHeight
                contentFrame:SetHeight(math.max(0.1, totalHeight))
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
                        width,
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
                contentFrame._wnAccordionFullH = sectionYOffset
                if sectionYOffset > 0 then
                    contentFrame:SetHeight(sectionYOffset)
                else
                    contentFrame:SetHeight(0.1)
                end
            end
        elseif emptyMessage and emptyMessage ~= "" then
            local emptyText = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
            emptyText:SetPoint("TOP", contentFrame, "TOP", 0, -20)
            emptyText:SetText("|cff999999" .. emptyMessage .. "|r")
            emptyText:SetWidth(width - 40)
            emptyText:SetJustifyH("CENTER")
            sectionYOffset = sectionYOffset + 50
            contentFrame:SetHeight(math.max(0.1, sectionYOffset))
        end

        contentFrame._wnAccordionFullH = math.max(0.1, sectionYOffset)
        return sectionYOffset
    end

    local function AnchorSectionHeader(headerFrame)
        headerFrame:SetHeight(SECTION_H)
        if isFirstSection then
            headerFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
            headerFrame:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
            isFirstSection = false
        elseif previousSectionContent then
            headerFrame:SetPoint("TOPLEFT", previousSectionContent, "BOTTOMLEFT", SIDE_MARGIN, -SECTION_HEADER_GAP)
            headerFrame:SetPoint("TOPRIGHT", previousSectionContent, "BOTTOMRIGHT", -SIDE_MARGIN, -SECTION_HEADER_GAP)
        else
            headerFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
            headerFrame:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
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
        local favoritesVisualOpts = BuildAccordionVisualOpts({
            bodyGetter = function() return favoritesContent end,
            updateVisibleFn = CharactersVirtualScrollBump,
        }) or {
            animatedContent = function() return favoritesContent end,
        }
        favoritesVisualOpts.sectionPreset = "gold"
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
                        favoritesContent:SetHeight(math.max(0.1, favoritesContent._wnAccordionFullH or 0.1))
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
        if favIcon then favIcon:SetSize(28, 28) end

        local favCount = FontManager:CreateFontString(favHeader, "header", "OVERLAY")
        favCount:SetPoint("RIGHT", -14, 0)
        favCount:SetText("|cffaaaaaa" .. FormatNumber(#trackedFavorites) .. "|r")

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
            favoritesContent:SetHeight(math.max(0.1, favoritesContent._wnAccordionFullH or 0.1))
        else
            favoritesContent:Hide()
            favoritesContent:SetHeight(0.1)
        end
        previousSectionContent = favoritesContent
        yOffset = yOffset + SECTION_H + (favoritesExpanded and favoritesHeight or 0) + SECTION_HEADER_GAP
    end

    -- User-defined custom headers (tracked, non-favorite characters)
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
            local grpVisualOpts = BuildAccordionVisualOpts({
                bodyGetter = function() return grpContent end,
                updateVisibleFn = CharactersVirtualScrollBump,
            }) or { animatedContent = function() return grpContent end }
            grpVisualOpts.sectionPreset = isFavHeader and "gold" or "accent"
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
                            grpContent:SetHeight(math.max(0.1, grpContent._wnAccordionFullH or 0.1))
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
                })
            end

            grpContent = AcquireSectionContentFrame(grpHeader)
            local grpHeight = DrawCharactersIntoSection(
                grpContent,
                gList,
                false,
                gListKey,
                (ns.L and ns.L["CUSTOM_HEADER_EMPTY"]) or "No characters in this header. Use the + button (next to Filter) or row note icon on non-favorites to assign."
            )
            if grpExpanded then
                grpContent:Show()
                grpContent:SetHeight(math.max(0.1, grpContent._wnAccordionFullH or 0.1))
            else
                grpContent:Hide()
                grpContent:SetHeight(0.1)
            end
            previousSectionContent = grpContent
            yOffset = yOffset + SECTION_H + (grpExpanded and grpHeight or 0) + SECTION_HEADER_GAP
        end
    end

    -- Regular characters (ungrouped tracked, non-favorites)
    if drawRegular then
        local charactersExpanded = self.db.profile.ui.charactersExpanded
        local charactersContent
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
                        charactersContent:SetHeight(math.max(0.1, charactersContent._wnAccordionFullH or 0.1))
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
            BuildAccordionVisualOpts({
                bodyGetter = function() return charactersContent end,
                updateVisibleFn = CharactersVirtualScrollBump,
            }) or { animatedContent = function() return charactersContent end }
        )
        AnchorSectionHeader(charHeader)
        if charIcon then charIcon:SetSize(24, 24) end

        local charCount = FontManager:CreateFontString(charHeader, "header", "OVERLAY")
        charCount:SetPoint("RIGHT", -14, 0)
        charCount:SetText("|cffaaaaaa" .. FormatNumber(#trackedRegular) .. "|r")

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
            charactersContent:SetHeight(math.max(0.1, charactersContent._wnAccordionFullH or 0.1))
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
        local untrackedVisualOpts = BuildAccordionVisualOpts({
            bodyGetter = function() return untrackedContent end,
            updateVisibleFn = CharactersVirtualScrollBump,
        }) or {
            animatedContent = function() return untrackedContent end,
        }
        untrackedVisualOpts.sectionPreset = "danger"
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
                        untrackedContent:SetHeight(math.max(0.1, untrackedContent._wnAccordionFullH or 0.1))
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

        local untrackedCount = FontManager:CreateFontString(untrackedHeader, "header", "OVERLAY")
        untrackedCount:SetPoint("RIGHT", -14, 0)
        untrackedCount:SetText("|cff888888" .. FormatNumber(#untracked) .. "|r")

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
            untrackedContent:SetHeight(math.max(0.1, untrackedContent._wnAccordionFullH or 0.1))
        else
            untrackedContent:Hide()
            untrackedContent:SetHeight(0.1)
        end
        previousSectionContent = untrackedContent
        yOffset = yOffset + SECTION_H + (untrackedExpanded and untrackedHeight or 0)
    end
    
    return yOffset
end

--============================================================================
-- DRAW SINGLE CHARACTER ROW
--============================================================================

---@param existingRow Frame|nil When set (virtual list), draw into this pooled row instead of acquiring a second frame.
function WarbandNexus:DrawCharacterRow(parent, char, index, width, yOffset, isFavorite, showReorder, charList, listKey, positionInList, totalInList, currentPlayerKey, existingRow)
    local row = existingRow
    if not row then
        row = AcquireCharacterRow(parent)
    else
        row:SetParent(parent)
        row:Show()
        row:SetAlpha(1)
        if row.anim then row.anim:Stop() end
    end
    row:ClearAllPoints()
    row:SetSize(width, 46)  -- Increased 20% (38 → 46)
    row:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    row:EnableMouse(true)
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end

    -- Define charKey for use in buttons (canonical key for DB/service consistency)
    local charKey = GetCharKey(char)
    local isCurrent = IsCharLoggedInSession(char)
    
    -- Set alternating background colors (Factory pattern)
    ns.UI.Factory:ApplyRowBackground(row, index)

    -- Online character highlight (theme-aware)
    ns.UI.Factory:ApplyOnlineCharacterHighlight(row, isCurrent)

    -- Class color
    local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
    
    -- COLUMN 1: Favorite button
    local favOffset = GetColumnOffset("favorite")
    
    if not row.favButton then
        -- Helper creates button, attach to row
        row.favButton = CreateFavoriteButton(row, charKey, isFavorite, CHAR_ROW_COLUMNS.favorite.width, "LEFT", favOffset + (CHAR_ROW_COLUMNS.favorite.spacing / 2), 0, nil)
        row.favButton.isPersistentRowElement = true  -- Mark as persistent to prevent cleanup
        -- Note: callback set below
    end
    -- Update state
    row.favButton.charKey = charKey
    row.favButton:SetChecked(isFavorite)
    
    -- Safely set OnClick (favButton should be a Button type)
    if row.favButton.HasScript and row.favButton:HasScript("OnClick") then
        row.favButton:SetScript("OnClick", function(btn)
            local newStatus = false
            if ns.CharacterService then
                newStatus = ns.CharacterService:ToggleFavoriteCharacter(WarbandNexus, charKey)
            end
            return newStatus
        end)
    end
    
    -- Tooltip for favorite button
    if ShowTooltip and row.favButton.SetScript then
        row.favButton:SetScript("OnEnter", function(self)
            local isFav = ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(WarbandNexus, charKey)
            ShowTooltip(self, {
                type = "custom",
                icon = "Interface\\Icons\\Achievement_GuildPerk_HappyHour",
                title = isFav and ((ns.L and ns.L["REMOVE_FROM_FAVORITES"]) or "Remove from Favorites") or ((ns.L and ns.L["ADD_TO_FAVORITES"]) or "Add to Favorites"),
                description = (ns.L and ns.L["FAVORITES_TOOLTIP"]) or "Favorite characters appear at the top of the list",
                lines = {
                    {text = "|cff00ff00" .. ((ns.L and ns.L["CLICK_TO_TOGGLE"]) or "Click to toggle") .. "|r", color = {1, 1, 1}}
                },
                anchor = "ANCHOR_RIGHT"
            })
        end)
        
        row.favButton:SetScript("OnLeave", function(self)
            if HideTooltip then
                HideTooltip()
            end
        end)
    end
    
    
    -- Icon border color (accent) — used for profession icons
    local iconBorderColor = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    
    -- COLUMN 2: Faction icon
    local factionOffset = GetColumnOffset("faction")
    if char.faction then
        if not row.factionIcon then
            row.factionIcon = CreateFactionIcon(row, char.faction, CHAR_ROW_COLUMNS.faction.width, "LEFT", factionOffset + (CHAR_ROW_COLUMNS.faction.spacing / 2), 0)
        end
        if char.faction == "Alliance" then
            row.factionIcon:SetAtlas("AllianceEmblem")
        elseif char.faction == "Horde" then
            row.factionIcon:SetAtlas("HordeEmblem")
        else
            row.factionIcon:SetAtlas("bfa-landingbutton-alliance-up")
        end
        row.factionIcon:Show()
    elseif row.factionIcon then
        row.factionIcon:Hide()
    end
    
    
    -- COLUMN 3: Race icon
    local raceOffset = GetColumnOffset("race")
    if char.raceFile then
        if not row.raceIcon then
            row.raceIcon = CreateRaceIcon(row, char.raceFile, char.gender, CHAR_ROW_COLUMNS.race.width, "LEFT", raceOffset + (CHAR_ROW_COLUMNS.race.spacing / 2), 0)
        end
        local raceAtlas = ns.UI_GetRaceGenderAtlas(char.raceFile, char.gender)
        row.raceIcon:SetAtlas(raceAtlas)
        row.raceIcon:Show()
    elseif row.raceIcon then
        row.raceIcon:Hide()
    end
    
    
    -- COLUMN 4: Class icon
    local classOffset = GetColumnOffset("class")
    if char.classFile then
        if not row.classIcon then
            row.classIcon = CreateClassIcon(row, char.classFile, CHAR_ROW_COLUMNS.class.width, "LEFT", classOffset + (CHAR_ROW_COLUMNS.class.spacing / 2), 0)
        end
        row.classIcon:SetAtlas("classicon-" .. char.classFile)
        row.classIcon:Show()
    elseif row.classIcon then
        row.classIcon:Hide()
    end
    
    
    -- COLUMN 5: Name
    local nameOffset = GetColumnOffset("name")
    local nameLeftPadding = 4
    
    if not row.nameText then
        row.nameText = FontManager:CreateFontString(row, "subtitle", "OVERLAY")
        row.nameText:SetPoint("TOPLEFT", nameOffset + nameLeftPadding, -8)
        row.nameText:SetWidth(CHAR_ROW_COLUMNS.name.width)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetNonSpaceWrap(false)
        row.nameText:SetMaxLines(1)
    end
    row.nameText:SetText(string.format("|cff%02x%02x%02x%s|r",
        classColor.r * 255, classColor.g * 255, classColor.b * 255,
        char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")))
    if char.hasMail then
        if not row.mailIcon then
            row.mailIcon = row:CreateTexture(nil, "OVERLAY")
            row.mailIcon:SetSize(14, 14)
        end
        ApplyPendingMailIconTexture(row.mailIcon)
        row.mailIcon:ClearAllPoints()
        row.mailIcon:SetPoint("LEFT", row.nameText, "LEFT", row.nameText:GetStringWidth() + 3, -1)
        row.mailIcon:Show()
    elseif row.mailIcon then
        row.mailIcon:Hide()
    end
    if not row.realmText then
        row.realmText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.realmText:SetPoint("TOPLEFT", nameOffset + nameLeftPadding, -23)
        row.realmText:SetWidth(CHAR_ROW_COLUMNS.name.width)
        row.realmText:SetJustifyH("LEFT")
        row.realmText:SetWordWrap(false)
        row.realmText:SetNonSpaceWrap(false)  -- Prevent long word overflow
        row.realmText:SetMaxLines(1)  -- Single line only
        row.realmText:SetTextColor(1, 1, 1)
    end
    local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    row.realmText:SetText("|cffb0b0b8" .. displayRealm .. "|r")
    
    -- COLUMN: Guild — width from max guild name; text centered; strictly between Name and Level
    local guildOffset = nameOffset + (CHAR_ROW_COLUMNS.name.total or 115)
    local guildColW = self._charListMaxGuildWidth or (CHAR_ROW_COLUMNS.guild and CHAR_ROW_COLUMNS.guild.width) or 130
    local guildSpacing = (CHAR_ROW_COLUMNS.guild and CHAR_ROW_COLUMNS.guild.spacing) or 15
    if not row.guildText then
        row.guildText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.guildText:SetJustifyH("CENTER")
        if row.guildText.SetJustifyV then row.guildText:SetJustifyV("MIDDLE") end
        row.guildText:SetWordWrap(false)
        row.guildText:SetNonSpaceWrap(false)
        row.guildText:SetMaxLines(1)
    end
    row.guildText:ClearAllPoints()
    local rowH = row:GetHeight() or 46
    local centerY = -rowH / 2
    row.guildText:SetPoint("CENTER", row, "TOPLEFT", guildOffset + (guildColW - 4) / 2, centerY)
    row.guildText:SetWidth(guildColW - 4)
    row.guildText:SetText(BuildGuildText(char, isCurrent))
    row.guildText:Show()

    -- Left class tint: ends at name/realm column only (does not extend under guild column).
    do
        local nameLeft = nameOffset + nameLeftPadding
        local nameColW = CHAR_ROW_COLUMNS.name.width
        local swName = row.nameText:GetStringWidth() or 0
        local swRealm = row.realmText:GetStringWidth() or 0
        local mailExtra = 0
        if row.mailIcon and row.mailIcon:IsShown() then
            mailExtra = (row.mailIcon:GetWidth() or 14) + 4
        end
        local nameBlockRight = nameLeft + math.min(nameColW, math.max(swName, swRealm) + mailExtra + 4)
        local gradientEnd = nameBlockRight
        local rowW = row:GetWidth() or 800
        if gradientEnd > rowW - 2 then
            gradientEnd = rowW - 2
        end
        if ns.UI_ApplyCharacterRowClassGradientAccent then
            ns.UI_ApplyCharacterRowClassGradientAccent(row, char.classFile, gradientEnd)
        end
    end
    
    -- Level column: level + rested line (DB-driven).
    local guildTotal = guildColW + guildSpacing
    local levelOffset = guildOffset + guildTotal
    local levelColW = CHAR_ROW_COLUMNS.level.width
    if not row.levelText then
        row.levelText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.levelText:SetWidth(levelColW)
        row.levelText:SetJustifyH("CENTER")
        row.levelText:SetWordWrap(false)
        row.levelText:SetMaxLines(1)
    end

    if not row.levelRestedText then
        row.levelRestedText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.levelRestedText:SetWidth(levelColW)
        row.levelRestedText:SetJustifyH("CENTER")
        row.levelRestedText:SetWordWrap(false)
        row.levelRestedText:SetMaxLines(1)
    end

    local restedState = self.GetCharacterRestedState and self:GetCharacterRestedState(char)
    local maxPlayerLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 80
    local showRestedLine = restedState ~= nil and (char.level or 1) < maxPlayerLevel
    local showZzz = restedState and restedState.isRestingArea

    row.levelText:ClearAllPoints()
    if showRestedLine then
        row.levelText:SetPoint("TOP", row, "TOPLEFT", levelOffset + (levelColW / 2), -7)
    else
        row.levelText:SetPoint("LEFT", levelOffset, 0)
    end
    row.levelText:SetText(string.format("|cff%02x%02x%02x%d|r",
        classColor.r * 255, classColor.g * 255, classColor.b * 255,
        char.level or 1))
    row.levelText:Show()

    if showRestedLine then
        local restedPct = restedState.restedPercentOfLevel or 0
        row.levelRestedText:ClearAllPoints()
        row.levelRestedText:SetPoint("TOP", row.levelText, "BOTTOM", 0, -2)
        if showZzz then
            row.levelRestedText:SetText(string.format("|cff66c0ffZzz %.2f%%|r", restedPct))
        else
            row.levelRestedText:SetText(string.format("|cff66c0ff%.2f%%|r", restedPct))
        end
        row.levelRestedText:Show()
    else
        row.levelRestedText:Hide()
    end

    if row.levelRestedIcon then row.levelRestedIcon:Hide() end
    if row.levelRestedHitFrame then row.levelRestedHitFrame:Hide() end

    -- COLUMN: Item Level (dynamic offset, chained from level column)
    local itemLevelOffset = levelOffset + (CHAR_ROW_COLUMNS.level.total or 97)
    if not row.itemLevelText then
        row.itemLevelText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.itemLevelText:SetWidth(CHAR_ROW_COLUMNS.itemLevel.width)
        row.itemLevelText:SetJustifyH("CENTER")
        row.itemLevelText:SetMaxLines(1)  -- Single line only
    end
    row.itemLevelText:ClearAllPoints()
    row.itemLevelText:SetPoint("LEFT", itemLevelOffset, 0)
    local itemLevel = char.itemLevel or 0
    if itemLevel > 0 then
        row.itemLevelText:SetText(string.format("|cffffd700%s %d|r", (ns.L and ns.L["ILVL_SHORT"]) or "iLvl", itemLevel))
    else
        row.itemLevelText:SetText("|cff666666--|r")
    end
    
    
    -- COLUMN 8: Gold (dynamic offset, chained from itemLevel column)
    local goldOffset = itemLevelOffset + (CHAR_ROW_COLUMNS.itemLevel.total or 90)
    if not row.goldText then
        row.goldText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.goldText:SetWidth(CHAR_ROW_COLUMNS.gold.width)
        row.goldText:SetJustifyH("RIGHT")
        row.goldText:SetMaxLines(1)  -- Single line only
    end
    row.goldText:ClearAllPoints()
    row.goldText:SetPoint("LEFT", goldOffset, 0)
    local totalCopper = ns.Utilities:GetCharTotalCopper(char)
    row.goldText:SetText(FormatMoney(totalCopper, 12))
    
    
    -- COLUMN 9: Professions (dynamic offset, chained from gold column)
    local profOffset = goldOffset + (CHAR_ROW_COLUMNS.gold.total or 205)
    if not row.profIcons then row.profIcons = {} end
    
    -- Hide all existing profession icons first
    for i = 1, #row.profIcons do
        row.profIcons[i]:Hide()
    end
    
    if char.professions then
        local iconSize = 39  -- Increased 15% (34 → 39)
        local iconSpacing = 5  -- Icon spacing
        
        -- Count total professions first
        local numProfs = 0
        if char.professions[1] then numProfs = numProfs + 1 end
        if char.professions[2] then numProfs = numProfs + 1 end
        for i = 1, #SECONDARY_PROF_KEYS do
            local sec = SECONDARY_PROF_KEYS[i]
            if char.professions[sec] then numProfs = numProfs + 1 end
        end
        
        -- Calculate centered starting position (within column content area, excluding right spacing)
        local profColumnWidth = CHAR_ROW_COLUMNS.professions.width  -- Content width only
        local totalIconWidth = (numProfs * iconSize) + ((numProfs - 1) * iconSpacing)
        -- Center the icons within the column width
        local leftPadding = (profColumnWidth - totalIconWidth) / 2
        local currentProfX = profOffset + leftPadding
        
        local charKey = GetCharKey(char)
        local function SetupProfIcon(prof, idx, profSlotKey)
            if not prof or not prof.icon then return end
            
            -- Reuse or create (with accent border)
            local pFrame = row.profIcons[idx]
            if not pFrame then
                pFrame = CreateIcon(row, nil, iconSize, false, iconBorderColor, false)
                pFrame:EnableMouse(true)
                pFrame.icon = pFrame.texture
                
                row.profIcons[idx] = pFrame
            end
            
            -- Clear previous position and set new centered position
            pFrame:ClearAllPoints()
            pFrame:SetPoint("LEFT", currentProfX, 0)
            pFrame.icon:SetTexture(prof.icon)
            pFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Crop default WoW icon border
            pFrame:Show()
            
            -- Unspent knowledge badge (yellow dot)
            local profName = prof.name
            local kd = nil
            if profName and char.knowledgeData then
                -- Prefer highest skillLineID (newest expansion) for current data
                local bestKey = -1
                for key, entry in pairs(char.knowledgeData) do
                    if type(key) == "number" and type(entry) == "table" and entry.professionName == profName then
                        if key > bestKey then
                            bestKey = key
                            kd = entry
                        end
                    end
                end
                -- Fallback: legacy profName-keyed data
                if not kd then
                    kd = char.knowledgeData[profName]
                end
            end
            if kd and kd.unspentPoints and kd.unspentPoints > 0 then
                if not pFrame.knowledgeBadge then
                    local badge = pFrame:CreateTexture(nil, "OVERLAY")
                    badge:SetSize(16, 16)
                    badge:SetPoint("TOPRIGHT", pFrame, "TOPRIGHT", 5, 0)
                    badge:SetAtlas("icons_64x64_important")
                    pFrame.knowledgeBadge = badge
                end
                pFrame.knowledgeBadge:Show()
            else
                if pFrame.knowledgeBadge then
                    pFrame.knowledgeBadge:Hide()
                end
            end
            
            -- Profession detail is now shown automatically when WoW's profession UI opens.
            -- No click action needed on these icons.
            pFrame:SetScript("OnMouseUp", nil)
            
            -- Setup tooltip with detailed information (expansion skills + knowledge + concentration)
            pFrame:SetScript("OnEnter", function(self)
                local profName = prof.name or ((ns.L and ns.L["UNKNOWN_PROFESSION"]) or "Unknown Profession")
                local lines = {}

                -- ====== SECTION 1: Expansion sub-professions (skill levels) ======
                local expansions = char.professionExpansions and char.professionExpansions[profName]
                if expansions and #expansions > 0 then
                    for i = 1, #expansions do
                        local exp = expansions[i]
                        local skillColor
                        local maxSkill = exp.maxSkillLevel or 0
                        local curSkill = exp.skillLevel or 0

                        if maxSkill > 0 and curSkill >= maxSkill then
                            skillColor = {0.3, 0.9, 0.3}
                        elseif curSkill > 0 then
                            skillColor = {1.0, 0.82, 0.0}
                        else
                            skillColor = {0.4, 0.4, 0.4}
                        end

                        local skillText
                        if maxSkill > 0 then
                            skillText = string.format("%d / %d", curSkill, maxSkill)
                        else
                            skillText = "—"
                        end

                        lines[#lines + 1] = {
                            left = exp.name or "?",
                            right = skillText,
                            leftColor = {1, 1, 1},
                            rightColor = skillColor
                        }
                    end
                else
                    -- Fallback: no expansion data yet, show basic skill
                    if prof.skill and prof.maxSkill then
                        lines[#lines + 1] = {
                            left = profName,
                            right = string.format("%d / %d", prof.skill, prof.maxSkill),
                            leftColor = {1, 1, 1},
                            rightColor = {0.3, 0.9, 0.3}
                        }
                    end
                end

                -- ====== SECTION 2: Knowledge Data (C_Traits) ======
                local kd = nil
                if char.knowledgeData then
                    -- Prefer highest skillLineID (newest expansion) for current data
                    local bestKey = -1
                    for kKey, kEntry in pairs(char.knowledgeData) do
                        if type(kKey) == "number" and type(kEntry) == "table" and kEntry.professionName == profName then
                            if kKey > bestKey then
                                bestKey = kKey
                                kd = kEntry
                            end
                        end
                    end
                    -- Fallback: legacy profName-keyed data
                    if not kd then
                        kd = char.knowledgeData[profName]
                    end
                end
                if kd then
                    local unspent = kd.unspentPoints or 0
                    local spent = kd.spentPoints or 0
                    local maxPts = kd.maxPoints or 0
                    local collectible = (maxPts > 0) and (maxPts - unspent - spent) or 0
                    local hasKnowledgeLine = (collectible > 0) or (unspent > 0)
                    if hasKnowledgeLine then
                        lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                        local cName = kd.currencyName or ((ns.L and ns.L["KNOWLEDGE"]) or "Knowledge")
                        if collectible > 0 then
                            lines[#lines + 1] = {
                                left = (ns.L and ns.L["COLLECTIBLE"]) or "Collectible",
                                right = tostring(collectible),
                                leftColor = {1, 1, 1},
                                rightColor = {0.3, 0.9, 0.3}
                            }
                        end
                        if unspent > 0 then
                            lines[#lines + 1] = {
                                left = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t " .. unspent .. " " .. ((ns.L and ns.L["UNSPENT_POINTS"]) or "Unspent Points"),
                                leftColor = {1, 0.82, 0}
                            }
                        end
                    end
                end

                -- ====== SECTION 3: Concentration ======
                local concData = char.concentration and char.concentration[profName]
                if concData and concData.max and concData.max > 0 then
                    -- Spacer
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }

                    -- Estimate current concentration (passive regen since snapshot)
                    local estimated = concData.current or 0
                    if WarbandNexus and WarbandNexus.GetEstimatedConcentration then
                        estimated = WarbandNexus:GetEstimatedConcentration(concData)
                    end

                    local concColor = {1, 1, 1}
                    if estimated >= concData.max then
                        concColor = {0.3, 0.9, 0.3}
                    elseif estimated > 0 then
                        concColor = {1, 0.82, 0}
                    end

                    local concText = string.format("%d / %d", estimated, concData.max)

                    lines[#lines + 1] = {
                        left = (ns.L and ns.L["CONCENTRATION"]) or "Concentration",
                        right = concText,
                        leftColor = {1, 1, 1},
                        rightColor = concColor
                    }

                    -- Recharge timer (white label, yellow duration)
                    if estimated < concData.max and WarbandNexus and WarbandNexus.GetConcentrationTimeToFull then
                        local timeStr = WarbandNexus:GetConcentrationTimeToFull(concData)
                        if timeStr and timeStr ~= "" and timeStr ~= ((ns.L and ns.L["FULL"]) or "Full") then
                            lines[#lines + 1] = {
                                left = (ns.L and ns.L["RECHARGE"]) or "Recharge",
                                right = timeStr,
                                leftColor = {1, 1, 1},
                                rightColor = {1, 0.82, 0}
                            }
                        end
                    end
                end

                -- ====== SECTION 4: Profession equipment (per-profession only; no fallback to avoid showing wrong profession's equipment) ======
                local eqByProf = char.professionEquipment
                local eqData = eqByProf and eqByProf[profName] or nil
                if eqData and (eqData.tool or eqData.accessory1 or eqData.accessory2) then
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                    local slotKeys = { "tool", "accessory1", "accessory2" }
                    local tooltipSvc = ns.TooltipService
                    for i = 1, #slotKeys do
                        local slotKey = slotKeys[i]
                        local item = eqData[slotKey]
                        if item then
                            local iconStr = item.icon and string.format("|T%s:0|t ", tostring(item.icon)) or ""
                            -- Get stat lines first to extract actual slot type (Head, Chest, Tool, etc.)
                            local statLines = tooltipSvc and tooltipSvc.GetItemTooltipSummaryLines and tooltipSvc:GetItemTooltipSummaryLines(item.itemLink, item.itemID, slotKey) or {}
                            -- First line contains the slot type (e.g., "Head", "Chest", "Tool")
                            local slotLabel = (statLines[1] and statLines[1].left)
                                or (slotKey == "tool" and ((ns.L and ns.L["TOOL"]) or "Tool") or ((ns.L and ns.L["ACCESSORY"]) or "Accessory"))
                            lines[#lines + 1] = {
                                left = iconStr .. (item.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")),
                                right = slotLabel,
                                leftColor = {1, 1, 1},
                                rightColor = {0.5, 0.5, 0.5},
                            }
                            -- Add remaining stat lines (skip first since it's now used as slot label)
                            for si = 2, #statLines do
                                local sLine = statLines[si]
                                lines[#lines + 1] = {
                                    left = "    " .. sLine.left,
                                    right = sLine.right or "",
                                    leftColor = sLine.leftColor or {0.7, 0.7, 0.7},
                                    rightColor = sLine.rightColor or {0.7, 0.7, 0.7},
                                }
                            end
                        end
                    end
                end

                if not ShowTooltip then
                    -- Fallback: Use TooltipService
                    local tooltipLines = {}
                    for i = 1, #lines do
                        local line = lines[i]
                        if line.right then
                            tooltipLines[#tooltipLines + 1] = {
                                text = (line.left or "") .. "  " .. (line.right or ""),
                                color = line.rightColor or line.leftColor or {1, 1, 1}
                            }
                        elseif line.left and line.left ~= " " then
                            tooltipLines[#tooltipLines + 1] = {
                                text = line.left,
                                color = line.leftColor or {1, 1, 1}
                            }
                        end
                    end
                    ns.TooltipService:Show(self, {
                        type = "custom",
                        icon = prof.icon,
                        title = profName,
                        lines = tooltipLines,
                    })
                    return
                end

                ShowTooltip(self, {
                    type = "custom",
                    icon = prof.icon,
                    title = profName,
                    lines = lines,
                    anchor = "ANCHOR_RIGHT"
                })
            end)
            pFrame:SetScript("OnLeave", function(self)
                if HideTooltip then
                    HideTooltip()
                else
                    ns.TooltipService:Hide()
                end
            end)
            
            return true
        end
        
        local pIdx = 1
        -- Primary
        if char.professions[1] then
            SetupProfIcon(char.professions[1], pIdx, 1)
            pIdx = pIdx + 1
            currentProfX = currentProfX + iconSize + iconSpacing
        end
        if char.professions[2] then
            SetupProfIcon(char.professions[2], pIdx, 2)
            pIdx = pIdx + 1
            currentProfX = currentProfX + iconSize + iconSpacing
        end
        -- Secondary
        for i = 1, #SECONDARY_PROF_KEYS do
            local sec = SECONDARY_PROF_KEYS[i]
            if char.professions[sec] then
                SetupProfIcon(char.professions[sec], pIdx, sec)
                pIdx = pIdx + 1
                currentProfX = currentProfX + iconSize + iconSpacing
            end
        end
    end
    
    
    -- COLUMN 10: Mythic Keystone (dynamic offset, chained from professions column)
    local mythicKeyOffset = profOffset + (CHAR_ROW_COLUMNS.professions.total or 150)
    
    -- Create keystone icon (shared for has-key and no-key)
    if not row.keystoneIcon then
        row.keystoneIcon = row:CreateTexture(nil, "ARTWORK")
        row.keystoneIcon:SetSize(24, 24)  -- Increased 20% (20 → 24)

        -- Use atlas with fallback
        local atlasInfo = C_Texture.GetAtlasInfo("ChromieTime-32x32")
        if atlasInfo then
            row.keystoneIcon:SetAtlas("ChromieTime-32x32", true)
        else
            row.keystoneIcon:SetTexture(525134)  -- Fallback to item texture
            row.keystoneIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    row.keystoneIcon:ClearAllPoints()
    row.keystoneIcon:SetPoint("LEFT", mythicKeyOffset + 5, 0)  -- 5px padding from column edge

    -- Create keystone text (shared for has-key and no-key)
    if not row.keystoneText then
        row.keystoneText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.keystoneText:SetWidth(CHAR_ROW_COLUMNS.mythicKey.width - 30)
        row.keystoneText:SetJustifyH("LEFT")
        row.keystoneText:SetWordWrap(false)
        row.keystoneText:SetNonSpaceWrap(false)  -- Prevent long word overflow
        row.keystoneText:SetMaxLines(1)  -- Single line only
    end
    row.keystoneText:ClearAllPoints()
    row.keystoneText:SetPoint("LEFT", mythicKeyOffset + 34, 0)  -- Icon(24) + gap(5) + padding(5)
    
    -- Format content based on keystone status
    if char.mythicKey and char.mythicKey.level and char.mythicKey.level > 0 then
        -- HAS KEY: +Level • Dungeon (colored, bright icon)
        local dungeonAbbrev = char.mythicKey.dungeonName:sub(1, 4):upper()
        local keystoneText = string.format("|cffff8000+%d|r |cff999999•|r |cffffd700%s|r", 
            char.mythicKey.level, dungeonAbbrev)
        
        row.keystoneText:SetText(keystoneText)
        
        -- Bright, colored icon
        row.keystoneIcon:SetDesaturated(false)
        row.keystoneIcon:SetVertexColor(1, 1, 1)
        row.keystoneIcon:SetAlpha(1.0)
    else
        -- NO KEY: +0 • None (dimmed, desaturated icon)
        local keystoneText = "|cff888888+0|r |cff666666•|r |cffaaaaaa" .. ((ns.L and ns.L["NONE_LABEL"]) or "None") .. "|r"
        
        row.keystoneText:SetText(keystoneText)
        
        -- Dimmed, desaturated icon
        row.keystoneIcon:SetDesaturated(true)
        row.keystoneIcon:SetVertexColor(0.6, 0.6, 0.6)
        row.keystoneIcon:SetAlpha(0.4)
    end
    
    row.keystoneIcon:Show()
    row.keystoneText:Show()
    
    -- RIGHT-ANCHORED COLUMNS: [Delete] [Header assign] [LastSeen] [Reorder]
    local R_MARGIN = 6
    local R_GAP = 6
    local deleteRight = R_MARGIN
    local headerAssignRight = deleteRight + CHAR_ROW_COLUMNS.delete.width + R_GAP
    local lastSeenRight = headerAssignRight + (CHAR_ROW_COLUMNS.headerAssign and CHAR_ROW_COLUMNS.headerAssign.total or 26) + R_GAP
    local reorderRight = lastSeenRight + CHAR_ROW_COLUMNS.lastSeen.width + R_GAP
    
    if row.trackingIcon then
        row.trackingIcon:Hide()
    end
    
    -- Reorder Buttons (right-aligned column, centered content)
    if not row.reorderButtons then
        local rb = ns.UI.Factory:CreateContainer(row, CHAR_ROW_COLUMNS.reorder.width, 46)
        rb:SetAlpha(0.7)
        rb.isPersistentRowElement = true
        
        rb.up = ns.UI.Factory:CreateButton(rb, 18, 18, true)
        rb.up:SetPoint("CENTER", -11, 0)
        rb.up:SetNormalAtlas("housing-floor-arrow-up-default")
        rb.up:EnableMouse(true)
        rb.down = ns.UI.Factory:CreateButton(rb, 18, 18, true)
        rb.down:SetPoint("CENTER", 11, 0)
        rb.down:SetNormalAtlas("housing-floor-arrow-down-default")
        rb.down:EnableMouse(true)
        row.reorderButtons = rb
    end
    row.reorderButtons:ClearAllPoints()
    row.reorderButtons:SetPoint("RIGHT", row, "RIGHT", -reorderRight, 0)
    
    if showReorder and charList then
        row.reorderButtons:Show()
        -- Always set OnClick (WoW Button supports SetScript even without prior script; HasScript can be false before first set)
        if row.reorderButtons.up then
            row.reorderButtons.up:EnableMouse(true)
            row.reorderButtons.up:SetScript("OnClick", function() WarbandNexus:ReorderCharacter(char, charList, listKey, -1) end)
        end
        if row.reorderButtons.down then
            row.reorderButtons.down:EnableMouse(true)
            row.reorderButtons.down:SetScript("OnClick", function() WarbandNexus:ReorderCharacter(char, charList, listKey, 1) end)
        end
    else
        row.reorderButtons:Hide()
        if row.reorderButtons.up then row.reorderButtons.up:SetScript("OnClick", nil) end
        if row.reorderButtons.down then row.reorderButtons.down:SetScript("OnClick", nil) end
    end
    
    
    -- COLUMN: Last Seen (RIGHT-anchored, compact)
    if isCurrent then
        if not row.onlineText then
            row.onlineText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.onlineText:SetWidth(CHAR_ROW_COLUMNS.lastSeen.width)
            row.onlineText:SetJustifyH("CENTER")
            row.onlineText:SetText((ns.L and ns.L["ONLINE"]) or "Online")
            row.onlineText:SetTextColor(0, 1, 0) 
        end
        row.onlineText:ClearAllPoints()
        row.onlineText:SetPoint("RIGHT", -lastSeenRight, 0)
        row.onlineText:Show()
        if row.lastSeenText then row.lastSeenText:Hide() end
    else
        if row.onlineText then row.onlineText:Hide() end
        
        local timeDiff = char.lastSeen and (time() - char.lastSeen) or math.huge
        
        if not row.lastSeenText then
            row.lastSeenText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.lastSeenText:SetWidth(CHAR_ROW_COLUMNS.lastSeen.width)
            row.lastSeenText:SetJustifyH("CENTER")
        end
        row.lastSeenText:ClearAllPoints()
        row.lastSeenText:SetPoint("RIGHT", -lastSeenRight, 0)
        
        local lastSeenStr = ""
        if timeDiff < 60 then
            lastSeenStr = (ns.L and ns.L["TIME_LESS_THAN_MINUTE"]) or "< 1m ago"
        elseif timeDiff < 3600 then
            local minutesFormat = (ns.L and ns.L["TIME_MINUTES_FORMAT"]) or "%dm ago"
            lastSeenStr = string.format(minutesFormat, math.floor(timeDiff / 60))
        elseif timeDiff < 86400 then
            local hoursFormat = (ns.L and ns.L["TIME_HOURS_FORMAT"]) or "%dh ago"
            lastSeenStr = string.format(hoursFormat, math.floor(timeDiff / 3600))
        else
            local daysFormat = (ns.L and ns.L["TIME_DAYS_FORMAT"]) or "%dd ago"
            lastSeenStr = string.format(daysFormat, math.floor(timeDiff / 86400))
        end
        row.lastSeenText:SetText(lastSeenStr)
        row.lastSeenText:SetTextColor(1, 1, 1)
        row.lastSeenText:Show()
    end
    
    
    -- COLUMN: Custom section assign (folder) — tracked non-favorites in regular or custom group lists
    local showHeaderAssign = (char.isTracked ~= false) and (not isFavorite)
        and (listKey == "regular" or (ns.CharacterService and ns.CharacterService.ParseCustomGroupIdFromListKey(listKey)))
    if showHeaderAssign then
        if not row.headerAssignBtn then
            local hb = ns.UI.Factory:CreateButton(row, 22, 22, true)
            hb.isPersistentRowElement = true
            local htex = hb.GetNormalTexture and hb:GetNormalTexture()
            if htex then
                htex:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
                htex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            row.headerAssignBtn = hb
        end
        row.headerAssignBtn:ClearAllPoints()
        row.headerAssignBtn:SetPoint("CENTER", row, "RIGHT", -(headerAssignRight + 11), 0)
        row.headerAssignBtn:Show()
        row.headerAssignBtn:SetScript("OnClick", function(selfBtn)
            if ns.UI_ShowCharacterSectionAssignMenu then
                ns.UI_ShowCharacterSectionAssignMenu(selfBtn, charKey, WarbandNexus.db.profile, function()
                    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
                end)
            end
        end)
        if ShowTooltip then
            row.headerAssignBtn:SetScript("OnEnter", function(selfBtn)
                ShowTooltip(selfBtn, {
                    type = "custom",
                    title = (ns.L and ns.L["CUSTOM_HEADER_ASSIGN_TOOLTIP_TITLE"]) or "Custom header",
                    description = (ns.L and ns.L["CUSTOM_HEADER_ASSIGN_TOOLTIP_DESC"]) or "Move this character into a header. Use the + button (left of Filter) to create headers, or Filter → New custom header.",
                    anchor = "ANCHOR_LEFT",
                })
            end)
            row.headerAssignBtn:SetScript("OnLeave", HideTooltip)
        end
    elseif row.headerAssignBtn then
        row.headerAssignBtn:Hide()
    end

    -- COLUMN: Delete button (RIGHT-anchored, compact)
    if not isCurrent then
        if not row.deleteBtn then
            local deleteBtn = ns.UI.Factory:CreateButton(row, 24, 24, true)
            deleteBtn.isPersistentRowElement = true
            
            -- Add icon texture
            local icon = deleteBtn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            icon:SetDesaturated(true)
            icon:SetVertexColor(0.8, 0.2, 0.2)
            deleteBtn.texture = icon
            deleteBtn.icon = icon
            
            row.deleteBtn = deleteBtn
        end
        row.deleteBtn:ClearAllPoints()
        row.deleteBtn:SetPoint("CENTER", row, "RIGHT", -(deleteRight + 12), 0)
        
        row.deleteBtn.charKey = charKey
        row.deleteBtn.charName = char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        
        -- Safely set OnClick
        if row.deleteBtn.HasScript and row.deleteBtn:HasScript("OnClick") then
            row.deleteBtn:SetScript("OnClick", function(self)
                -- Use custom themed delete dialog
                local charKey = self.charKey
                local charName = self.charName
                
                -- Get UI functions from namespace
                local COLORS = ns.UI_COLORS
                local CreateExternalWindow = ns.UI_CreateExternalWindow
                local CreateThemedButton = ns.UI_CreateThemedButton
                local FontManager = ns.FontManager
                
                if not CreateExternalWindow then
                    DebugPrint("[WarbandNexus] ERROR: CreateExternalWindow not found!")
                    return
                end
                
                -- Create custom delete confirmation dialog
                local dialog, contentFrame = CreateExternalWindow({
                    name = "DeleteCharacterDialog",
                    title = (ns.L and ns.L["DELETE_CHARACTER_TITLE"]) or "Delete Character?",
                    icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
                    width = 420,
                    height = 180,
                })
                
                if not dialog then
                    DebugPrint("[WarbandNexus] ERROR: Failed to create delete dialog!")
                    return
                end
                
                -- Warning text
                local warning = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
                warning:SetPoint("TOP", contentFrame, "TOP", 0, -20)
                warning:SetWidth(380)
                warning:SetJustifyH("CENTER")
                warning:SetTextColor(1, 0.85, 0.1)  -- Gold/Orange
                local confirmDeleteFmt = (ns.L and ns.L["CONFIRM_DELETE"]) or "Are you sure you want to delete |cff00ccff%s|r?"
                warning:SetText(string.format(confirmDeleteFmt, charName or ((ns.L and ns.L["THIS_CHARACTER"]) or "this character")))
                
                local subtext = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
                subtext:SetPoint("TOP", warning, "BOTTOM", 0, -10)
                subtext:SetWidth(380)
                subtext:SetJustifyH("CENTER")
                subtext:SetTextColor(1, 0.3, 0.3)  -- Red
                local cannotUndoText = (ns.L and ns.L["CANNOT_UNDO"]) or "This action cannot be undone!"
                subtext:SetText("|cffff0000" .. cannotUndoText .. "|r")
                
                -- Buttons container (using Factory pattern)
                local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, 320, 40)
                btnContainer:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 20)
                
                -- Delete button (LEFT)
                local deleteBtnLabel = (ns.L and ns.L["DELETE"]) or "Delete"
                local deleteBtn = CreateThemedButton and CreateThemedButton(btnContainer, deleteBtnLabel, 150, 36) or CreateFrame("Button", nil, btnContainer)
                if not CreateThemedButton then
                    deleteBtn:SetSize(150, 36)
                    deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
                    deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
                    deleteBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
                    
                    local deleteBtnText = deleteBtn:CreateFontString(nil, "OVERLAY")
                    deleteBtnText:SetPoint("CENTER")
                    FontManager:SafeSetFont(deleteBtnText, "body")
                    deleteBtnText:SetText(deleteBtnLabel)
                end
                deleteBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
                deleteBtn:SetScript("OnClick", function()
                    local success = WarbandNexus:DeleteCharacter(charKey)
                    if dialog.Close then
                        dialog:Close()
                    else
                        dialog:Hide()
                    end
                end)
                
                -- Cancel button (RIGHT)
                local cancelBtnLabel = (ns.L and ns.L["CANCEL"]) or "Cancel"
                local cancelBtn = CreateThemedButton and CreateThemedButton(btnContainer, cancelBtnLabel, 150, 36) or CreateFrame("Button", nil, btnContainer)
                if not CreateThemedButton then
                    cancelBtn:SetSize(150, 36)
                    cancelBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
                    cancelBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
                    cancelBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
                    
                    local cancelBtnText = cancelBtn:CreateFontString(nil, "OVERLAY")
                    cancelBtnText:SetPoint("CENTER")
                    FontManager:SafeSetFont(cancelBtnText, "body")
                    cancelBtnText:SetText(cancelBtnLabel)
                end
                cancelBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
                cancelBtn:SetScript("OnClick", function()
                    if dialog.Close then
                        dialog:Close()
                    else
                        dialog:Hide()
                    end
                end)
                
                -- NOTE: Do NOT override dialog:SetScript("OnHide") here!
                -- WindowFactory's OnHide handles hiding the clickOutsideFrame overlay.
                -- Overriding it leaves an invisible full-screen mouse blocker.
                -- dialog.Close() already handles SetParent(nil) and _G cleanup.
                
                -- Show dialog
                dialog:Show()
            end)
        end
        
        -- Tooltip for delete button
        if ShowTooltip and row.deleteBtn.SetScript then
            row.deleteBtn:SetScript("OnEnter", function(self)
                local removeFromTrackingFmt = (ns.L and ns.L["REMOVE_FROM_TRACKING_FORMAT"]) or "Remove %s from tracking"
                ShowTooltip(self, {
                    type = "custom",
                    icon = "Interface\\Icons\\Spell_Shadow_SacrificialShield",
                    title = (ns.L and ns.L["DELETE_CHARACTER"]) or "Delete Character",
                    titleColor = {1, 0.4, 0},
                    description = string.format(removeFromTrackingFmt, self.charName or ((ns.L and ns.L["THIS_CHARACTER"]) or "this character")),
                    lines = {
                        {text = "|cffff0000" .. ((ns.L and ns.L["CANNOT_UNDO"]) or "This action cannot be undone!") .. "|r", color = {1, 0.2, 0.2}},
                        {type = "spacer"},
                        {text = "|cff00ff00" .. ((ns.L and ns.L["CLICK_TO_DELETE"]) or "Click to delete") .. "|r", color = {1, 1, 1}}
                    },
                    anchor = "ANCHOR_LEFT"
                })
            end)
            
            row.deleteBtn:SetScript("OnLeave", function(self)
                if HideTooltip then
                    HideTooltip()
                end
            end)
        end
        
        row.deleteBtn:Show()
    else
        if row.deleteBtn then
            row.deleteBtn:Hide()
            -- Clear OnClick when hiding
            if row.deleteBtn.HasScript and row.deleteBtn:HasScript("OnClick") then
                row.deleteBtn:SetScript("OnClick", nil)
            end
        end
    end
    

    
    local betweenRows = GetLayout().betweenRows or 0
    return yOffset + 46 + betweenRows, row  -- Row 46px + spacing + row ref for pool tracking
end


--============================================================================
-- REORDER CHARACTER IN LIST
--============================================================================

function WarbandNexus:ReorderCharacter(char, charList, listKey, direction)
    if not char or not listKey then
        return
    end
    
    local charKey = GetCharKey(char)
    local favoriteKeySet = (ns.CharacterService and ns.CharacterService.BuildFavoriteKeySet)
        and ns.CharacterService:BuildFavoriteKeySet(self) or {}
    
    -- Don't update lastSeen when reordering (keep current timestamps)
    local currentPlayerKey = ns.Utilities:GetCharacterKey()
    
    -- Get or initialize custom order
    if not self.db.profile.characterOrder then
        self.db.profile.characterOrder = {
            favorites = {},
            regular = {},
            untracked = {},
        }
    end
    
    if not self.db.profile.characterOrder[listKey] then
        self.db.profile.characterOrder[listKey] = {}
    end
    
    local customOrder = self.db.profile.characterOrder[listKey]
    
    -- If no custom order exists, seed from GetAllCharacters order for this category (online char first).
    if #customOrder == 0 then
        local allChars = self:GetAllCharacters()
        local keysInCategory = {}
        for i = 1, #allChars do
            local c = allChars[i]
            local key = GetCharKey(c)
            if key then
                local isTracked = c.isTracked ~= false
                local isFav = false
                if ns.CharacterService then
                    isFav = (ns.CharacterService.IsFavoriteFromKeySet and ns.CharacterService:IsFavoriteFromKeySet(favoriteKeySet, key))
                        or ns.CharacterService:IsFavoriteCharacter(self, key)
                end
                local inCategory = false
                if listKey == "favorites" then
                    inCategory = isTracked and isFav
                elseif listKey == "regular" then
                    local gid = (ns.CharacterService and ns.CharacterService.GetCharacterCustomSectionId)
                        and ns.CharacterService:GetCharacterCustomSectionId(self, key)
                        or (self.db.profile.characterGroupAssignments or {})[key]
                    inCategory = isTracked and not isFav and (gid == nil or gid == "")
                elseif listKey == "untracked" then
                    inCategory = not isTracked
                elseif ns.CharacterService and ns.CharacterService.ParseCustomGroupIdFromListKey then
                    local grpId = ns.CharacterService:ParseCustomGroupIdFromListKey(listKey)
                    if grpId then
                        local gid = (ns.CharacterService and ns.CharacterService.GetCharacterCustomSectionId)
                            and ns.CharacterService:GetCharacterCustomSectionId(self, key)
                            or (self.db.profile.characterGroupAssignments or {})[key]
                        inCategory = isTracked and not isFav and gid == grpId
                    end
                end
                if inCategory then
                    keysInCategory[#keysInCategory + 1] = key
                end
            end
        end
        local seen = {}
        if currentPlayerKey then
            for i = 1, #keysInCategory do
                if OrderKeyIsSessionChar(keysInCategory[i]) then
                    customOrder[1] = keysInCategory[i]
                    seen[keysInCategory[i]] = true
                    break
                end
            end
        end
        for i = 1, #keysInCategory do
            local k = keysInCategory[i]
            if not seen[k] then
                customOrder[#customOrder + 1] = k
                seen[k] = true
            end
        end
    end
    
    -- Find current index in custom order
    local currentIndex = nil
    for i = 1, #customOrder do
        local key = customOrder[i]
        if key == charKey then
            currentIndex = i
            break
        end
    end
    
    if not currentIndex then 
        -- Character not in custom order, add it
        tinsert(customOrder, charKey)
        currentIndex = #customOrder
    end
    
    -- Calculate new index
    local newIndex = currentIndex + direction
    
    if newIndex < 1 or newIndex > #customOrder then
        return
    end
    
    -- Swap in custom order
    customOrder[currentIndex], customOrder[newIndex] = customOrder[newIndex], customOrder[currentIndex]

    -- Logged-in character stays at top of this section after any reorder (matches DrawCharacterList).
    if currentPlayerKey then
        for i = 1, #customOrder do
            if OrderKeyIsSessionChar(customOrder[i]) then
                if i > 1 then
                    local c = tremove(customOrder, i)
                    tinsert(customOrder, 1, c)
                end
                break
            end
        end
    end
    
    -- Save and refresh
    self.db.profile.characterOrder[listKey] = customOrder
    
    local tk = ResolveSessionCharactersTableKey() or currentPlayerKey
    if self.db.global.characters and tk and self.db.global.characters[tk] then
        self.db.global.characters[tk].lastSeen = time()
    end
    
    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
end

--============================================================================
-- CUSTOM CHARACTER HEADERS — dialogs (Filter menu entry points)
--============================================================================

function WarbandNexus:OpenCustomCharacterHeaderDialog()
    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local CreateThemedButton = ns.UI_CreateThemedButton
    local FontMgr = ns.FontManager
    if not CreateExternalWindow or not ns.UI or not ns.UI.Factory or not ns.UI.Factory.CreateEditBox or not ns.UI_CreateCustomHeaderRosterPicker then
        return
    end
    local L = ns.L
    local profile = self.db and self.db.profile
    local characters = (self.GetAllCharacters and self:GetAllCharacters()) or {}
    local dialogW = 820
    local innerW = dialogW - 36
    local dialog, contentFrame = CreateExternalWindow({
        name = "WnNewCustomHeaderDialog",
        title = (L and L["CUSTOM_HEADER_NEW_DIALOG_TITLE"]) or "New custom section",
        icon = "socialqueuing-icon-group",
        iconIsAtlas = true,
        width = dialogW,
        height = 620,
    })
    if not dialog or not contentFrame or not profile then return end

    local hint = FontMgr:CreateFontString(contentFrame, "body", "OVERLAY")
    hint:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 16, -10)
    hint:SetWidth(innerW)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    if hint.SetWordWrap then hint:SetWordWrap(true) end
    hint:SetTextColor(0.78, 0.80, 0.84)
    hint:SetText((L and L["CUSTOM_HEADER_NEW_DIALOG_HINT"]) or "Name (max 32). Search and tick optional. Enter in name saves.")

    local nameLabel = FontMgr:CreateFontString(contentFrame, "tabSubtitle", "OVERLAY")
    nameLabel:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
    nameLabel:SetWidth(innerW)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetTextColor(1, 0.92, 0.55)
    nameLabel:SetText((L and L["CUSTOM_HEADER_NEW_DIALOG_LABEL"]) or "Section name")

    local editBg = ns.UI.Factory:CreateContainer(contentFrame, innerW, 44, true)
    editBg:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -8)
    editBg:SetPoint("TOPRIGHT", nameLabel, "BOTTOMRIGHT", 0, -8)
    local eb = ns.UI.Factory:CreateEditBox(editBg)
    if eb.SetPoint then
        eb:SetPoint("TOPLEFT", editBg, "TOPLEFT", 10, -8)
        eb:SetPoint("BOTTOMRIGHT", editBg, "BOTTOMRIGHT", -10, 6)
    end
    eb:SetMaxLetters(32)
    eb:SetAutoFocus(true)

    local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, innerW, 40)
    btnContainer:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 14)
    local okLbl = (L and L["CUSTOM_HEADER_NEW_DIALOG_CREATE"]) or "Create section"
    local cancelLbl = CANCEL or "Cancel"

    local host = CreateFrame("Frame", nil, contentFrame)
    host:SetPoint("LEFT", contentFrame, "LEFT", 16, 0)
    host:SetPoint("RIGHT", contentFrame, "RIGHT", -16, 0)
    host:SetPoint("TOP", editBg, "BOTTOM", 0, -10)
    host:SetPoint("BOTTOM", btnContainer, "TOP", 0, 12)

    local picker = ns.UI_CreateCustomHeaderRosterPicker(host, innerW, WarbandNexus, profile, characters, nil)
    if picker and picker.frame then
        picker.frame:SetAllPoints(host)
    end

    local function trySubmit()
        local t = eb:GetText()
        if type(t) == "string" then
            t = t:match("^%s*(.-)%s*$") or ""
        else
            t = ""
        end
        if t == "" or (issecretvalue and issecretvalue(t)) then
            return
        end
        local addedId
        if ns.CharacterService and ns.CharacterService.AddCustomCharacterSection then
            addedId = ns.CharacterService:AddCustomCharacterSection(WarbandNexus, t)
        end
        if not addedId then
            return
        end
        if picker and picker.GetSelectedKeys and ns.CharacterService and ns.CharacterService.SetCharacterCustomSection then
            local keys = picker.GetSelectedKeys()
            for i = 1, #keys do
                local raw = keys[i]
                if raw then
                    local k = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey and ns.Utilities:GetCanonicalCharacterKey(raw)) or raw
                    ns.CharacterService:SetCharacterCustomSection(WarbandNexus, k, addedId)
                end
            end
        end
        if dialog.Close then dialog:Close() else dialog:Hide() end
        WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
    end

    eb:SetScript("OnEnterPressed", function()
        trySubmit()
    end)

    local okBtn = CreateThemedButton and CreateThemedButton(btnContainer, okLbl, 168, 34)
    if okBtn then
        okBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
        okBtn:SetScript("OnClick", trySubmit)
    end
    local cancelBtn = CreateThemedButton and CreateThemedButton(btnContainer, cancelLbl, 150, 34)
    if cancelBtn then
        cancelBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
        cancelBtn:SetScript("OnClick", function()
            if dialog.Close then dialog:Close() else dialog:Hide() end
        end)
    end
    dialog:Show()
    if picker and picker.Rebuild and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if picker.Rebuild then picker.Rebuild() end
        end)
    end
end

--- Modal roster editor for an existing custom header ([+] same UX as new section dialog).
function WarbandNexus:OpenCustomHeaderRosterWindow(groupId)
    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local CreateThemedButton = ns.UI_CreateThemedButton
    local FontMgr = ns.FontManager
    if not groupId or not CreateExternalWindow or not ns.UI_CreateCustomHeaderRosterPicker then return end
    local profile = self.db and self.db.profile
    local characters = (self.GetAllCharacters and self:GetAllCharacters()) or {}
    if not profile then return end
    local L = ns.L
    local gtitle = tostring(groupId)
    local groups = profile.characterCustomGroups or {}
    for gi = 1, #groups do
        if groups[gi].id == groupId then
            gtitle = groups[gi].name or gtitle
            break
        end
    end
    local dialogW = 820
    local innerW = dialogW - 36
    local safeName = "WnHdrRoster_" .. tostring(groupId):gsub("[^%a%d_]", "_")
    local dialog, contentFrame = CreateExternalWindow({
        name = safeName,
        title = gtitle,
        icon = "socialqueuing-icon-group",
        iconIsAtlas = true,
        width = dialogW,
        height = 620,
    })
    if not dialog or not contentFrame then return end

    local hint = FontMgr:CreateFontString(contentFrame, "body", "OVERLAY")
    hint:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 16, -10)
    hint:SetWidth(innerW)
    hint:SetJustifyH("LEFT")
    if hint.SetWordWrap then hint:SetWordWrap(true) end
    hint:SetTextColor(0.78, 0.80, 0.84)
    hint:SetText((L and L["CUSTOM_HEADER_ROSTER_WINDOW_HINT"]) or "First list: boxes start checked (still in this section). Uncheck to queue a removal. Second list: tick to queue adds. Nothing is saved until you click Add selected.")

    local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, innerW, 40)
    btnContainer:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 14)
    local addLbl = (L and L["CUSTOM_HEADER_ADD_SELECTED"]) or "Add selected"
    local closeLbl = (L and L["CUSTOM_HEADER_ROSTER_CLOSE"]) or "Close"

    local host = CreateFrame("Frame", nil, contentFrame)
    host:SetPoint("LEFT", contentFrame, "LEFT", 16, 0)
    host:SetPoint("RIGHT", contentFrame, "RIGHT", -16, 0)
    host:SetPoint("TOP", hint, "BOTTOM", 0, -10)
    host:SetPoint("BOTTOM", btnContainer, "TOP", 0, 12)

    local picker = ns.UI_CreateCustomHeaderRosterPicker(host, innerW, WarbandNexus, profile, characters, groupId)
    if picker and picker.frame then
        picker.frame:SetAllPoints(host)
    end

    local addBtn = CreateThemedButton and CreateThemedButton(btnContainer, addLbl, 200, 34)
    if addBtn and picker and picker.ApplyPendingAdds then
        addBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
        addBtn:SetScript("OnClick", function()
            picker.ApplyPendingAdds()
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end)
    end
    local closeBtn = CreateThemedButton and CreateThemedButton(btnContainer, closeLbl, 160, 34)
    if closeBtn then
        closeBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
        closeBtn:SetScript("OnClick", function()
            if dialog.Close then dialog:Close() else dialog:Hide() end
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end)
    end
    dialog:Show()
    if picker and picker.Rebuild and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if picker.Rebuild then picker.Rebuild() end
        end)
    end
end

function WarbandNexus:ConfirmDeleteCustomCharacterHeader(groupId, groupName)
    local CreateExternalWindow = ns.UI_CreateExternalWindow
    local CreateThemedButton = ns.UI_CreateThemedButton
    local FontMgr = ns.FontManager
    if not groupId or not CreateExternalWindow then return end
    local dialog, contentFrame = CreateExternalWindow({
        name = "WnDeleteCustomHeaderDialog",
        title = (ns.L and ns.L["CUSTOM_HEADER_DELETE_DIALOG_TITLE"]) or "Delete custom header?",
        icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
        width = 420,
        height = 190,
    })
    if not dialog or not contentFrame then return end
    local nm = groupName or groupId
    local warn = FontMgr:CreateFontString(contentFrame, "body", "OVERLAY")
    warn:SetPoint("TOP", contentFrame, "TOP", 0, -20)
    warn:SetWidth(380)
    warn:SetJustifyH("CENTER")
    local fmt = (ns.L and ns.L["CUSTOM_HEADER_DELETE_DIALOG_BODY"]) or "Remove header |cffffcc00%s|r and ungroup its characters?"
    warn:SetText(string.format(fmt, nm))

    local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, 360, 40)
    btnContainer:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 20)
    local delBtn = CreateThemedButton and CreateThemedButton(btnContainer, (ns.L and ns.L["DELETE"]) or "Delete", 150, 36)
    if delBtn then
        delBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
        delBtn:SetScript("OnClick", function()
            if ns.CharacterService and ns.CharacterService.RemoveCustomCharacterSection then
                ns.CharacterService:RemoveCustomCharacterSection(WarbandNexus, groupId)
            end
            if dialog.Close then dialog:Close() else dialog:Hide() end
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end)
    end
    local cancelBtn = CreateThemedButton and CreateThemedButton(btnContainer, (ns.L and ns.L["CANCEL"]) or "Cancel", 150, 36)
    if cancelBtn then
        cancelBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
        cancelBtn:SetScript("OnClick", function()
            if dialog.Close then dialog:Close() else dialog:Hide() end
        end)
    end
    dialog:Show()
end
