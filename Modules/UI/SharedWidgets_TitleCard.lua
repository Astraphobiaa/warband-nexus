--[[
    Warband Nexus - SharedWidgets TitleCard (split from SharedWidgets.lua)
    Tab header icons, standard tab title card, character icons, title toolbar metrics.
    Loaded right after Modules/UI/SharedWidgets.lua (TOC) so every later file still finds these ns.UI_* exports.
]]

local _, ns = ...
assert(ns.UI and ns.UI_ApplyVisuals and ns.UI_CreateCard, "SharedWidgets_TitleCard: load after SharedWidgets.lua")
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
local FontManager = ns.FontManager
local GetPixelScale = ns.GetPixelScale
local SnapRuleTexture = ns.UI_SnapRuleTexture
local COLORS = ns.UITheme.COLORS
local UI_SPACING = ns.UI_SPACING
local IsClassicModeEnabled = ns.UI_IsClassicMode
local ApplyStandardTitleCardChrome = ns.UI_ApplyStandardTitleCardChrome
local ApplyStandardCardElevatedChrome = ns.UI_ApplyStandardCardElevatedChrome

--- Semantic UI role → category (FontManager.FONT_ROLE / single theme source)
local function UIFontRole(roleKey)
    return FontManager:GetFontRole(roleKey)
end

-- HEADER ICON SYSTEM (Standardized icon+border for all tab headers)

-- Centralized icon mapping for all tabs (keys match `Modules/UI.lua` MAIN_TAB_ORDER + legacy aliases).
local TAB_HEADER_ICONS = {
    chars = "warbands-icon",
    characters = "warbands-icon",
    items = "Banker",
    storage = "Quartermaster",
    plans = "poi-workorders",
    currency = "AzeriteReady",
    --- Overridden below for reputations vs reputation key
    reputations = "MajorFactions_MapIcons_Centaur64",
    reputation = "MajorFactions_MapIcons_Centaur64",
    pve = "Tormentors-Boss",
    pvp = "questlog-questtypeicon-pvp",
    stats = "racing",
    statistics = "racing",
    collections = "dragon-rostrum",
    professions = "Vehicle-HammerGold",
    gear = "VignetteEventElite",
    settings = ns.UI_GetIconAtlas("settings") or "mechagon-projects",
    about = "Campaign-QuestLog-Legendaryicon",
    qol = "Soulbinds_Tree_Conduit_Icon_Utility",
}

--- Blizzard `Interface\\Icons\\...` fallback when atlases reject (broken/missing art in some patches).
local TAB_NAV_TEXTURE_FALLBACK = {
    chars = "Interface\\Icons\\Achievement_Character_Human_Male",
    items = "Interface\\Icons\\INV_Misc_Bag_08",
    gear = "Interface\\Icons\\INV_Chest_Chain_06",
    currency = "Interface\\Icons\\INV_Misc_Coin_02",
    reputations = "Interface\\Icons\\Achievement_Reputation_01",
    pve = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
    pvp = "Interface\\Icons\\Achievement_PVP_A_A",
    professions = "Interface\\Icons\\Trade_Engineering",
    collections = "Interface\\Icons\\INV_Misc_Head_Dragon_Nexus",
    plans = "Interface\\Icons\\INV_Misc_Map_01",
    stats = "Interface\\Icons\\Achievement_General_StayClassy",
    settings = "Interface\\Icons\\Trade_Engineering",
    about = "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Credits.tga",
}


local function NormalizeMainNavTabMediaKey(tabKey)
    if not tabKey then return nil end
    local k = tabKey
    if k == "statistics" then return "stats" end
    if k == "reputation" then return "reputations" end
    if k == "characters" then return "chars" end
    if k == "storage" then return "items" end
    return k
end

-- Tab title header icon (CreateHeaderIcon)
local HEADER_ICON_SIZE = 44
local HEADER_ICON_PAD = 5
local HEADER_ICON_INSET = 12

-- Export icon mapping for external use
ns.UI_GetTabIcon = function(tabName)
    local key = tabName
    -- Main window uses `reputations`; some cards use `reputation`.
    if key == "reputation" or key == "reputations" then
        local ok, fg = pcall(UnitFactionGroup, "player")
        if ok and fg == "Alliance" then
            return "AllianceAssaultsMapBanner"
        end
        if ok and fg == "Horde" then
            return "HordeAssaultsMapBanner"
        end
        return TAB_HEADER_ICONS.reputations or "MajorFactions_MapIcons_Centaur64"
    end
    if key == "statistics" then
        key = "stats"
    end
    if key == "characters" then
        key = "chars"
    end
    return TAB_HEADER_ICONS[key]
        or TAB_HEADER_ICONS[tabName]
        or "shop-icon-housing-characters-up"
end

--- Title card glyph: atlas/tab icon in a square tile (never override atlas UV with icon crop).
---@return boolean usedAtlas
function ns.UI_ApplyTitleCardGlyph(tex, tabKey, atlasName)
    if not tex then return false end
    if atlasName and atlasName ~= "" then
        if pcall(tex.SetAtlas, tex, atlasName, false) or pcall(tex.SetAtlas, tex, atlasName, true) then
            return true
        end
    end
    if tabKey and ns.UI_ApplyMainNavTabGlyph then
        ns.UI_ApplyMainNavTabGlyph(tex, tabKey)
        return false
    end
    if not pcall(tex.SetAtlas, tex, "shop-icon-housing-characters-up", false) then
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if ns.UI_ApplyFileIconTexCoord then
            ns.UI_ApplyFileIconTexCoord(tex)
        else
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
    end
    return false
end

--- Main nav strip / rail: Blizzard atlas (`UI_GetTabIcon`) then built-in texture paths (packaged TGAs optional).
---@return boolean usedPackaged Unused; kept for call-site compatibility (always false when Media lacks matching files).
function ns.UI_ApplyMainNavTabGlyph(tex, tabKey)
    if not tex or not tabKey then return false end

    local atlasNm = ns.UI_GetTabIcon(tabKey)
    if atlasNm and type(atlasNm) == "string" then
        if pcall(tex.SetAtlas, tex, atlasNm, false) then
            return false
        end
        if pcall(tex.SetAtlas, tex, atlasNm, true) then
            return false
        end
    end

    local canon = NormalizeMainNavTabMediaKey(tabKey)
    local iconPath = canon and TAB_NAV_TEXTURE_FALLBACK[canon]
    if type(iconPath) == "string" and iconPath ~= "" then
        tex:SetTexture(iconPath)
        if ns.UI_ApplyFileIconTexCoord then
            ns.UI_ApplyFileIconTexCoord(tex)
        else
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        return false
    end

    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    if ns.UI_ApplyFileIconTexCoord then
        ns.UI_ApplyFileIconTexCoord(tex)
    else
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    return false
end

ns.UI_GetCharKey = function(char)
    if not char then return nil end
    if not ns.Utilities then return char._key end
    if ns.Utilities.ResolveCharacterRowKey then
        local rk = ns.Utilities:ResolveCharacterRowKey(char)
        if rk then return rk end
    end
    if char._key and ns.Utilities.GetCanonicalCharacterKey
        and not (issecretvalue and issecretvalue(char._key)) then
        local ck = ns.Utilities:GetCanonicalCharacterKey(char._key)
        if ck then return ck end
    end
    local g = char.guid
    if type(g) == "string" and not (issecretvalue and issecretvalue(g)) and g ~= "" then
        return g
    end
    local n, r = char.name, char.realm
    if ns.Utilities.GetCharacterKey and n and r
        and not (issecretvalue and (issecretvalue(n) or issecretvalue(r))) then
        return ns.Utilities:GetCharacterKey(n, r)
    end
    if char._key and not (issecretvalue and issecretvalue(char._key)) then
        return char._key
    end
    return nil
end

--- Canonical subsidiary storage key (currency/PvE/gear caches). Mirrors VaultButton_Data.GetCurrentCharKey.
---@param optionalCharKey string|nil
---@return string|nil
function ns.UI_GetSubsidiaryCharKey(optionalCharKey)
    local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey and WarbandNexus then
        local k = CS:ResolveSubsidiaryCharacterKey(WarbandNexus, optionalCharKey)
        if k then return k end
    end
    if optionalCharKey and optionalCharKey ~= ""
        and not (issecretvalue and issecretvalue(optionalCharKey)) then
        if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            return ns.Utilities:GetCanonicalCharacterKey(optionalCharKey) or optionalCharKey
        end
        return optionalCharKey
    end
    if ns.Utilities and ns.Utilities.GetCharacterStorageKey and WarbandNexus then
        local raw = ns.Utilities:GetCharacterStorageKey(WarbandNexus)
        if raw and ns.Utilities.GetCanonicalCharacterKey then
            return ns.Utilities:GetCanonicalCharacterKey(raw) or raw
        end
        return raw
    end
    return nil
end

---@return number centerX Icon block center offset from parent LEFT (for CENTER anchor).
function ns.UI_GetTitleCardIconCenterX(iconSize, pad, inset)
    iconSize = iconSize or HEADER_ICON_SIZE or 44
    pad = pad or HEADER_ICON_PAD or 5
    inset = inset or HEADER_ICON_INSET or 14
    return inset + pad + (iconSize * 0.5)
end

--[[
    Tab title icon: fixed square tile + centered glyph (does not stretch with card height).
    @param parent Frame
    @param atlasName string|nil
    @param options table|nil { tabKey, tileOuter, glyphSize }
    @return table { icon, border } — border is the outer host frame (layout anchor)
]]
local function CreateHeaderIcon(parent, atlasName, options)
    if type(atlasName) == "table" and options == nil then
        options = atlasName
        atlasName = options.atlasName
    end
    options = type(options) == "table" and options or {}
    local sp = UI_SPACING or {}
    local tileOuter = options.tileOuter or sp.TITLE_CARD_ICON_TILE_OUTER or 44

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(tileOuter, tileOuter)
    container:EnableMouse(false)

    local icon = container:CreateTexture(nil, "ARTWORK")
    local inset = options.glyphInset or sp.TITLE_CARD_ICON_GLYPH_PAD or 4
    icon:SetPoint("TOPLEFT", container, "TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -inset, inset)
    if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(false) end
    if icon.SetTexelSnappingBias then icon:SetTexelSnappingBias(0) end

    if ns.UI_ApplyTitleCardGlyph then
        ns.UI_ApplyTitleCardGlyph(icon, options.tabKey, atlasName)
    end
    icon:SetVertexColor(1, 1, 1, 1)

    return {
        icon = icon,
        border = container,
        tileOuter = tileOuter,
        glyphSize = tileOuter - (inset * 2),
    }
end

--- Items / Gear: open result lists on content tone (no viewport rim box or scroll fill band).
function ns.UI_ConfigureMainScrollViewportForTab(mainFrame, tab)
    if not mainFrame then return end
    local vp = mainFrame.viewportBorder
    local sc = mainFrame.scrollChild
    if not vp then return end

    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
        vp:SetBackdropColor(0, 0, 0, 0)
        if vp._wnViewportAtlasUnderlay and vp._wnViewportAtlasUnderlay.Hide then
            vp._wnViewportAtlasUnderlay:Hide()
        end
        if sc and sc._wnViewportCanvasFill and sc._wnViewportCanvasFill.Hide then
            sc._wnViewportCanvasFill:Hide()
        end
        return
    end

    local borderless = (tab == "items" or tab == "gear")

    if borderless then
        vp:SetBackdropColor(0, 0, 0, 0)
        if vp._wnViewportAtlasUnderlay and vp._wnViewportAtlasUnderlay.Hide then
            vp._wnViewportAtlasUnderlay:Hide()
        end
        if sc and sc._wnViewportCanvasFill and sc._wnViewportCanvasFill.Hide then
            sc._wnViewportCanvasFill:Hide()
        end
        if sc and sc._wnResultsAnnexSheet and sc._wnResultsAnnexSheet.Hide then
            sc._wnResultsAnnexSheet:Hide()
        end
        if sc and sc._wnScrollBottomFill and sc._wnScrollBottomFill.Hide then
            sc._wnScrollBottomFill:Hide()
        end
    else
        local vpColor = ns.UI_GetMainPanelBackgroundColor and ns.UI_GetMainPanelBackgroundColor()
            or (COLORS and COLORS.bg) or { 0.042, 0.042, 0.055, 0.98 }
        vp:SetBackdropColor(vpColor[1], vpColor[2], vpColor[3], vpColor[4] or 0.98)
        if ns.UI_ApplyViewportAtlasUnderlay and not vp._wnViewportAtlasUnderlay then
            ns.UI_ApplyViewportAtlasUnderlay(vp)
        elseif vp._wnViewportAtlasUnderlay and vp._wnViewportAtlasUnderlay.Show then
            vp._wnViewportAtlasUnderlay:Show()
            if ns.UI_RefreshViewportAtlasUnderlayTint then
                ns.UI_RefreshViewportAtlasUnderlayTint(vp)
            end
        end
    end
end

--- Accent rule under title icon + text block.
local function ApplyTitleCardUnderline(titleCard, leftAnchor, rightAnchor, sp)
    if not titleCard or not leftAnchor or not rightAnchor then return end
    if IsClassicModeEnabled() then
        if titleCard._wnTitleUnderline and titleCard._wnTitleUnderline.Hide then
            titleCard._wnTitleUnderline:Hide()
        end
        return
    end
    sp = sp or UI_SPACING or {}
    local ac = COLORS and COLORS.accent or { 0.5, 0.4, 0.7 }
    local ruleA = sp.TITLE_CARD_UNDERLINE_ALPHA or 0.5
    local rule = titleCard._wnTitleUnderline
    if not rule then
        rule = titleCard:CreateTexture(nil, "ARTWORK")
        titleCard._wnTitleUnderline = rule
    end
    rule:SetColorTexture(ac[1], ac[2], ac[3], ruleA)
    rule:SetHeight(GetPixelScale(titleCard))
    SnapRuleTexture(rule)
    rule:ClearAllPoints()
    rule:SetPoint("BOTTOMLEFT", leftAnchor, "BOTTOMLEFT", 0, -5)
    rule:SetPoint("BOTTOMRIGHT", rightAnchor, "BOTTOMRIGHT", 0, -5)
    rule:Show()
end

-- Export header icon system
ns.UI_CreateHeaderIcon = CreateHeaderIcon

--[[
    Characters-tab standard title row: accent card, ring icon centered at x=35 from left,
    stacked title (header) + subtitle (subtitle font), text block anchored from icon.
    @param headerParent Frame — typically fixedHeader
    @param opts table:
      cardHeight (number, default 70)
      textContainerWidth (number, default 200)
      atlasName (string|nil) — explicit atlas; if nil, tabKey + GetTabIcon
      tabKey (string|nil)
      titleText (string) — colored title (|cff...|r)
      subtitleText (string|nil)
      textRightInset (number|nil) — if set, text container also anchors RIGHT on card (room for header controls)
      skipApplyVisuals (boolean) — skip ApplyVisuals on card (rare)
    @return titleCard, headerIcon, textContainer, titleFs, subtitleFs
]]
--- Vertically center title + subtitle as a block inside the title card text column.
function ns.UI_LayoutTitleCardTextStack(textContainer, titleFs, subtitleFs, textW)
    if not textContainer or not titleFs then return end
    local sp = UI_SPACING or {}
    local gap = sp.TITLE_CARD_TEXT_STACK_GAP or 3
    local stack = textContainer._wnTextStack
    if not stack then
        stack = CreateFrame("Frame", nil, textContainer)
        stack:EnableMouse(false)
        textContainer._wnTextStack = stack
    end
    stack:ClearAllPoints()
    stack:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    stack:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
    stack:SetPoint("CENTER", textContainer, "CENTER", 0, 0)
    if textW then
        stack:SetWidth(textW)
    end

    titleFs:ClearAllPoints()
    titleFs:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, 0)
    titleFs:SetPoint("TOPRIGHT", stack, "TOPRIGHT", 0, 0)

    local hasSub = false
    if subtitleFs then
        local subText = subtitleFs:GetText()
        hasSub = subText and not (issecretvalue and issecretvalue(subText)) and subText ~= ""
        subtitleFs:ClearAllPoints()
        if hasSub then
            subtitleFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -gap)
            subtitleFs:SetPoint("TOPRIGHT", stack, "TOPRIGHT", 0, 0)
            subtitleFs:Show()
        else
            subtitleFs:Hide()
        end
    end

    local titleH = titleFs:GetStringHeight() or 0
    if titleH <= 0 then titleH = 14 end
    local subH = 0
    if hasSub and subtitleFs then
        subH = subtitleFs:GetStringHeight() or 0
        if subH <= 0 then subH = 12 end
    end
    stack:SetHeight(titleH + (hasSub and (gap + subH) or 0))
end

local function CreateStandardTabTitleCard(headerParent, opts)
    if not headerParent or type(opts) ~= "table" then return nil end
    local sp = UI_SPACING or {}
    local cardH = opts.cardHeight or sp.TITLE_CARD_DEFAULT_HEIGHT or 64
    local textW = opts.textContainerWidth or 200
    local tileOuter = opts.tileOuter or sp.TITLE_CARD_ICON_TILE_OUTER or 44
    local contentPadH = opts.contentPadH or sp.TITLE_CARD_CONTENT_PAD_H or sp.TITLE_CARD_ICON_SIDE_INSET or 12
    local iconSideInset = opts.iconSideInset
    if iconSideInset == nil then
        iconSideInset = contentPadH
    end
    local ringGap = opts.textGap or sp.TITLE_CARD_RING_TEXT_GAP or 8
    local textPadV = sp.TITLE_CARD_TEXT_PAD_V or 8
    local iconTopInset = math.max(0, math.floor((cardH - tileOuter) * 0.5))

    local titleCard = CreateFrame("Frame", nil, headerParent)
    titleCard:Hide()
    titleCard:SetHeight(cardH)
    if not opts.skipApplyVisuals then
        if ApplyStandardTitleCardChrome then
            ApplyStandardTitleCardChrome(titleCard)
        elseif ApplyStandardCardElevatedChrome then
            ApplyStandardCardElevatedChrome(titleCard)
        end
    end
    local atlas = opts.atlasName
    if (not atlas or atlas == "") and opts.tabKey and ns.UI_GetTabIcon then
        atlas = ns.UI_GetTabIcon(opts.tabKey)
    end
    local headerIcon = CreateHeaderIcon(titleCard, atlas, {
        tabKey = opts.tabKey,
        tileOuter = tileOuter,
        glyphInset = opts.glyphInset or sp.TITLE_CARD_ICON_GLYPH_PAD,
    })
    headerIcon.border:ClearAllPoints()
    headerIcon.border:SetPoint("TOPLEFT", titleCard, "TOPLEFT", iconSideInset, -iconTopInset)

    local textContainer = ns.UI.Factory:CreateContainer(titleCard, textW, math.max(36, cardH - textPadV * 2))
    local textStack = CreateFrame("Frame", nil, textContainer)
    textStack:EnableMouse(false)
    textContainer._wnTextStack = textStack

    local titleFs = FontManager:CreateFontString(textStack, UIFontRole("tabTitlePrimary"), "OVERLAY")
    -- Strip any embedded |cAARRGGBB..|r colour so every tab title renders in the card's white
    -- ("Bright") colour. Several tabs wrap their title in the accent colour; user wants white titles.
    local titleStr = opts.titleText or ""
    if type(titleStr) == "string" then
        titleStr = titleStr:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
    end
    titleFs:SetText(titleStr)
    titleFs:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(titleFs, "Bright")

    local subtitleFs = FontManager:CreateFontString(textStack, UIFontRole("tabSubtitle"), "OVERLAY")
    subtitleFs:SetText(opts.subtitleText or "")
    ns.UI_SetTextColorRole(subtitleFs, "Normal")
    subtitleFs:SetJustifyH("LEFT")
    subtitleFs:SetWordWrap(false)
    subtitleFs:SetNonSpaceWrap(false)
    if subtitleFs.SetMaxLines then subtitleFs:SetMaxLines(1) end

    local rin = opts.textRightInset
    textContainer:ClearAllPoints()
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", ringGap, 0)
    local textRightPad = (type(rin) == "number" and rin > 0) and rin or contentPadH
    textContainer:SetPoint("RIGHT", titleCard, "RIGHT", -textRightPad, 0)
    textContainer:SetPoint("TOP", titleCard, "TOP", 0, -textPadV)
    textContainer:SetPoint("BOTTOM", titleCard, "BOTTOM", 0, textPadV)
    textContainer._wnTitleContentPadH = contentPadH

    ns.UI_LayoutTitleCardTextStack(textContainer, titleFs, subtitleFs, textW)
    textContainer._wnTitleFs = titleFs
    textContainer._wnSubtitleFs = subtitleFs

    if opts.showUnderline == true then
        ApplyTitleCardUnderline(titleCard, headerIcon.border, textContainer, sp)
    elseif titleCard._wnTitleUnderline then
        titleCard._wnTitleUnderline:Hide()
    end

    return titleCard, headerIcon, textContainer, titleFs, subtitleFs
end

--- Hide accent rule on a title card (e.g. cached headers rebuilt before underline removal).
function ns.UI_HideTitleCardUnderline(titleCard)
    if titleCard and titleCard._wnTitleUnderline then
        titleCard._wnTitleUnderline:Hide()
    end
end

ns.UI_CreateStandardTabTitleCard = CreateStandardTabTitleCard

--- Reapply icon + text layout after reparenting a cached title card (Collections, Storage).
function ns.UI_ReanchorStandardTabTitleLayout(headerIcon, titleCard, textContainer, cardHeight, textRightInset)
    if not headerIcon or not headerIcon.border or not titleCard then return end
    local sp = UI_SPACING or {}
    cardHeight = cardHeight or sp.TITLE_CARD_DEFAULT_HEIGHT or 64
    local tileOuter = sp.TITLE_CARD_ICON_TILE_OUTER or 44
    local contentPadH = sp.TITLE_CARD_CONTENT_PAD_H or sp.TITLE_CARD_ICON_SIDE_INSET or 12
    local iconSideInset = sp.TITLE_CARD_ICON_SIDE_INSET or contentPadH
    local ringGap = sp.TITLE_CARD_RING_TEXT_GAP or 8
    local textPadV = sp.TITLE_CARD_TEXT_PAD_V or 8
    local iconTopInset = math.max(0, math.floor((cardHeight - tileOuter) * 0.5))
    headerIcon.border:ClearAllPoints()
    headerIcon.border:SetPoint("TOPLEFT", titleCard, "TOPLEFT", iconSideInset, -iconTopInset)
    if textContainer then
        textContainer:ClearAllPoints()
        textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", ringGap, 0)
        local textRightPad = (type(textRightInset) == "number" and textRightInset > 0)
            and textRightInset
            or (textContainer._wnTitleContentPadH or contentPadH)
        textContainer:SetPoint("RIGHT", titleCard, "RIGHT", -textRightPad, 0)
        textContainer:SetPoint("TOP", titleCard, "TOP", 0, -textPadV)
        textContainer:SetPoint("BOTTOM", titleCard, "BOTTOM", 0, textPadV)
        if textContainer._wnTitleFs and ns.UI_LayoutTitleCardTextStack then
            ns.UI_LayoutTitleCardTextStack(textContainer, textContainer._wnTitleFs, textContainer._wnSubtitleFs)
        end
    end
    if titleCard._wnTitleUnderline then
        titleCard._wnTitleUnderline:Hide()
    end
end

-- CURRENT CHARACTER ICON (Global, easily customizable)

--[[
    Get the atlas name for "Current Character" icon
    This is a global setting that applies to all "Current Character" displays
    Change this function to customize the icon globally
    @return string - Atlas name for the current character icon
]]
local function GetCurrentCharacterIcon()
    -- CUSTOMIZE HERE: Change this atlas to change all "Current Character" icons
    -- Default: "charactercreate-gendericon-female-selected" (generic character icon)
    -- Alternatives: 
    --   "shop-icon-housing-characters-up" (house character)
    --   "charactercreate-icon-customize-body" (body customization)
    --   "Banker" (banker icon)
    return "charactercreate-gendericon-female-selected"
end

-- Export

-- CHARACTER-SPECIFIC ICON (Used in headers across multiple tabs)

--[[
    Get the atlas name for "Character-Specific" contexts
    This icon is used for headers and sections that represent character-specific data
    
    Used in:
    - Characters tab ÔåÆ "Characters" header
    - Storage tab ÔåÆ "Personal Banks" header
    - Reputations tab ÔåÆ "Character-Based Reputations" header
    
    @return string - Atlas name for character-specific icon
]]
local function GetCharacterSpecificIcon()
    -- CUSTOMIZE HERE: Change this atlas to change all character-specific headers
    -- Current: "honorsystem-icon-prestige-9" (honor prestige badge, character-specific indicator)
    -- Alternatives:
    --   "charactercreate-gendericon-female-selected" (generic character)
    --   "shop-icon-housing-characters-up" (house character)
    --   "charactercreate-icon-customize-body" (body customization)
    return "honorsystem-icon-prestige-9"
end

-- Export
ns.UI_GetCharacterSpecificIcon = GetCharacterSpecificIcon

--[[
    Get currency header icon texture path
    
    Returns appropriate icon for currency category headers. Never returns nil so that
    the UI never shows a question mark — unknown headers get a generic currency icon.
    Blizzard API does not provide icons for headers, so we use manual mapping.
    
    @param headerName string - Header name (e.g., "Legacy", "Midnight", "Season 1")
    @return string - Texture path (always non-nil)
]]
local function GetCurrencyHeaderIcon(headerName)
    if not headerName or headerName == "" then
        return "Interface\\Icons\\INV_Misc_Coin_01"
    end
    if issecretvalue and issecretvalue(headerName) then
        return "Interface\\Icons\\INV_Misc_Coin_01"
    end
    -- Legacy (all old expansions)
    if headerName:find("Legacy") then
        return "Interface\\Icons\\INV_Misc_Coin_01"
    -- Midnight (12.0) — night/shadow theme (path that exists in the client)
    elseif headerName:find("Midnight") or headerName:find("Quel'Thalas") or headerName:find("Coiled Isle") or headerName:find("Ula'tek") then
        return "Interface\\Icons\\Spell_Shadow_Teleport"
    -- Season headers (order matters: Season 1 before generic "Season"); all paths exist in-game
    elseif headerName:find("Season 1") or headerName:find("Season1") then
        return "Interface\\Icons\\Achievement_BG_winAB_underXminutes"
    elseif headerName:find("Season 2") or headerName:find("Season2") then
        return "Interface\\Icons\\Achievement_BG_winAB_underXminutes"
    elseif headerName:find("Season 3") or headerName:find("Season3") then
        return "Interface\\Icons\\Achievement_BG_winAB_underXminutes"
    elseif headerName:find("Season") then
        return "Interface\\Icons\\Achievement_BG_winAB_underXminutes"
    -- Expansions
    elseif headerName:find("War Within") then
        return "Interface\\Icons\\INV_Misc_Gem_Diamond_01"
    elseif headerName:find("Dragonflight") then
        return "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"
    elseif headerName:find("Shadowlands") then
        return "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
    elseif headerName:find("Battle for Azeroth") then
        return "Interface\\Icons\\INV_Sword_39"
    elseif headerName:find("Legion") then
        return "Interface\\Icons\\Spell_Shadow_Twilight"
    elseif headerName:find("Warlords of Draenor") or headerName:find("Draenor") then
        return "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc"
    elseif headerName:find("Mists of Pandaria") or headerName:find("Pandaria") then
        return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
    elseif headerName:find("Cataclysm") then
        return "Interface\\Icons\\Spell_Fire_Flameshock"
    elseif headerName:find("Wrath") or headerName:find("Lich King") then
        return "Interface\\Icons\\Spell_Shadow_SoulLeech_3"
    elseif headerName:find("Burning Crusade") or headerName:find("Outland") then
        return "Interface\\Icons\\Spell_Fire_FelFlameStrike"
    elseif headerName:find("PvP") or headerName:find("Player vs") then
        return "Interface\\Icons\\Achievement_BG_returnXflags_def_WSG"
    elseif headerName:find("Dungeon") or headerName:find("Raid") then
        return "Interface\\Icons\\achievement_boss_archaedas"
    elseif headerName:find("Miscellaneous") then
        return "Interface\\Icons\\INV_Misc_Gear_01"
    end
    -- Unknown header: generic currency-related icon (never use a question mark)
    return "Interface\\Icons\\INV_Misc_Coin_01"
end

-- Export
ns.UI_GetCurrencyHeaderIcon = GetCurrencyHeaderIcon

--[[
    Get class icon texture path (clean, frameless icons)
    @param classFile string - English class name (e.g., "WARRIOR", "MAGE")
    @return string - Texture path
]]

-- Character row column layout: Modules/UI/SharedWidgets_CharRow.lua (loaded before this file).

--- Title-card toolbar: horizontal anchor from `anchorTo` (RIGHT/LEFT); vertical centers with anchor target.
function ns.UI_AnchorTitleCardToolbarControl(btn, _titleCard, anchorTo, anchorPoint, offsetX)
    if not btn or not anchorTo then return end
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", anchorTo, anchorPoint or "RIGHT", offsetX or 0, 0)
end

--- Characters-reference toolbar metrics (64px card, 32px controls, 8px gaps, 0 edge inset).
---@return table metrics { btnH, squareBtn, gap, edgeInset, filterW, trailingGap }
function ns.UI_GetTitleCardToolbarMetrics()
    local sp = UI_SPACING or {}
    local btnH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
    return {
        btnH = btnH,
        squareBtn = btnH,
        gap = sp.HEADER_TOOLBAR_CONTROL_GAP or 8,
        edgeInset = sp.TITLE_CARD_TOOLBAR_EDGE_INSET or 0,
        filterW = 96,
        columnsW = 86,
        hideW = 84,
        toggleW = 88,
        actionW = 100,
        trailingGap = 10,
    }
end

--- Reserve width for title/subtitle text (right-to-left control chain on title card).
---@return number
function ns.UI_ComputeTitleToolbarReserve(widths, opts)
    local m = ns.UI_GetTitleCardToolbarMetrics()
    opts = opts or {}
    local total = m.edgeInset
    local n = widths and #widths or 0
    for i = 1, n do
        total = total + (widths[i] or 0)
        if i < n then
            total = total + m.gap
        end
    end
    if n > 0 then
        total = total + (opts.extraTrailingGap or m.trailingGap)
    end
    return total
end

--- Title-card toolbar reserve for Characters (Filter + custom section + gaps + right inset).
---@return number
local function ComputeCharactersTitleToolbarReserve()
    local m = ns.UI_GetTitleCardToolbarMetrics()
    return ns.UI_ComputeTitleToolbarReserve({ m.filterW, m.squareBtn })
end

-- Character sort/filter flyouts: SharedWidgets_CharacterFilter.lua (loaded after this file)


--- Hide legacy title-card expand/collapse-all controls (toolbar toggle removed).
function ns.UI_HideTitleCardExpandCollapseControls(ownerFrame)
    if not ownerFrame then return end
    if ownerFrame._wnExpandCollapseToggleBtn then ownerFrame._wnExpandCollapseToggleBtn:Hide() end
    if ownerFrame._wnExpandCollapseCollapseBtn then ownerFrame._wnExpandCollapseCollapseBtn:Hide() end
    if ownerFrame._wnExpandCollapseExpandBtn then ownerFrame._wnExpandCollapseExpandBtn:Hide() end
    if ownerFrame._wnCharactersExpandCollapseToggleBtn then ownerFrame._wnCharactersExpandCollapseToggleBtn:Hide() end
end

-- Exports (char row layout: SharedWidgets_CharRow.lua)
ns.UI_ComputeCharactersTitleToolbarReserve = ComputeCharactersTitleToolbarReserve
-- UI_GetTitleCardToolbarMetrics / UI_ComputeTitleToolbarReserve exported above

assert(ns.UI_CreateStandardTabTitleCard and ns.UI_GetCharKey and ns.UI_ComputeCharactersTitleToolbarReserve, "SharedWidgets_TitleCard: exports missing")
