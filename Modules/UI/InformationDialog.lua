--[[
    Warband Nexus - About / information content
    Shared between the legacy popup (optional) and Settings > About panel.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local UI_SPACING = ns.UI_SPACING

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

local function SemanticGoldRGB()
    if ns.UI_GetSemanticGoldColor then
        return ns.UI_GetSemanticGoldColor()
    end
    return 1, 0.84, 0, 1
end

local function SemanticGreenRGB()
    if ns.UI_GetSemanticGreenColor then
        return ns.UI_GetSemanticGreenColor()
    end
    return 0.2, 0.8, 0.2, 1
end

local function AccentRGB()
    local c = ns.UI_COLORS and ns.UI_COLORS.accent
    if c then return c[1], c[2], c[3] end
    return 0.4, 0.2, 0.58
end

local function GetDialogShellBg()
    if ns.UI_GetExternalShellBackdrop then
        return ns.UI_GetExternalShellBackdrop()
    end
    local c = ns.UI_COLORS
    return c and c.bg or { 0.06, 0.06, 0.08, 0.98 }
end

--- Paint credits, contributors, and tab guide copy into a bordered card.
---@param parent Frame scroll host or card parent
---@param innerWidth number usable text width
---@param opts table|nil `{ includeOkButton = bool, onOk = function }`
---@return number totalHeight
function ns.UI_PaintAboutContent(parent, innerWidth, opts)
    opts = opts or {}
    local COLORS = ns.UI_COLORS or { accent = { 0.40, 0.20, 0.58, 1 } }
    innerWidth = math.max(200, tonumber(innerWidth) or (parent and parent:GetWidth()) or 600)

    -- Plain container, not a card: UI_CreateCard paints a background and an accent border, and
    -- because this content lives inside the tab's scroll child that border scrolled along with
    -- the text. The window's own frame is the fixed border; the content scrolls inside it.
    local contentCard = (ns.UI.Factory and ns.UI.Factory.CreateContainer)
        and ns.UI.Factory:CreateContainer(parent, innerWidth, 100, false)
    if not contentCard then
        contentCard = CreateFrame("Frame", nil, parent)
    end
    contentCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    contentCard:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    contentCard:SetWidth(innerWidth)

    local yOffset = UI_SPACING.SCROLL_CONTENT_TOP_PADDING or 12
    local lastElement

    --- Font at a category's size scaled up, keeping the user's face and the AA policy.
    --- FontManager tops out at 16px ("header"), which is not enough separation for a page
    --- whose whole job is hierarchy.
    local function SetScaledFont(fs, category, scale)
        if not fs or not FontManager.GetFontFace then return end
        local path = FontManager:GetFontFace()
        local size = FontManager:GetFontSize(category) or 14
        -- GetAAFlags only honours coloredInk on its light-mode path; in dark mode it hands back
        -- the raw anti-aliasing preference, which is "" when the user turned outlines off. That
        -- silently dropped the weight from every heading here, so fall back explicitly.
        local flags = FontManager:GetAAFlags(category, { coloredInk = true })
        if flags == "" or flags == nil then
            flags = "OUTLINE"
        end
        pcall(fs.SetFont, fs, path, math.floor(size * (scale or 1) + 0.5), flags)
    end

    --- `scale` must be applied before the text is measured: GetStringHeight reflects the font
    --- in effect at that moment, so scaling afterwards would reserve the old, smaller height
    --- and the next element would overlap it.
    local function AddText(text, fontType, color, spacing, centered, scale)
        local fs = FontManager:CreateFontString(contentCard, fontType or "body", "OVERLAY")
        fs:SetPoint("TOPLEFT", contentCard, "TOPLEFT", UI_SPACING.SIDE_MARGIN + 2, -yOffset)
        fs:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -(UI_SPACING.SIDE_MARGIN + 2), -yOffset)
        fs:SetJustifyH(centered and "CENTER" or "LEFT")
        fs:SetWordWrap(true)
        if color then
            fs:SetTextColor(color[1], color[2], color[3])
        else
            ns.UI_SetTextColorRole(fs, "Normal")
        end
        -- Passing scale at all (even 1) re-applies the font, which is also what turns the
        -- coloredInk outline on -- that is how the accent lead-ins get their weight.
        if scale then
            SetScaledFont(fs, fontType or "body", scale)
        end
        fs:SetText(text)
        yOffset = yOffset + fs:GetStringHeight() + (spacing or 12)
        lastElement = fs
        return fs
    end

    -- Section rhythm: one accent for headings, gold for people's names, muted small for the
    -- labels that group them. The page used five competing hues (accent, gold, pink, class
    -- colours, green) with no separators, so nothing read as a level.
    local function AddDivider(spaceAbove, spaceBelow)
        yOffset = yOffset + (spaceAbove or 14)
        local div = ns.UI.Factory and ns.UI.Factory.CreateThemeDivider
            and ns.UI.Factory:CreateThemeDivider(contentCard, {
                orientation = "horizontal",
                variant = "section",
                thickness = 1,
            })
        if div then
            div:SetPoint("TOPLEFT", contentCard, "TOPLEFT", UI_SPACING.SIDE_MARGIN + 2, -yOffset)
            div:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -(UI_SPACING.SIDE_MARGIN + 2), -yOffset)
            yOffset = yOffset + 1
        end
        yOffset = yOffset + (spaceBelow or 14)
    end

    --- Lead paragraph: centred and capped, so it does not stretch to a 250-character line on a
    --- wide window the way the feature text used to.
    local function AddLeadParagraph(text, spacing)
        local fs = FontManager:CreateFontString(contentCard, "body", "OVERLAY")
        fs:SetPoint("TOP", contentCard, "TOP", 0, -yOffset)
        fs:SetWidth(math.min(innerWidth - (UI_SPACING.SIDE_MARGIN + 2) * 2, 780))
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(true)
        ns.UI_SetTextColorRole(fs, "Normal")
        fs:SetText(text)
        yOffset = yOffset + fs:GetStringHeight() + (spacing or 12)
        return fs
    end

    --- Centred line of already-coloured text (contributor rosters carry their own |c codes).
    local function AddRichLine(text, spacing)
        local fs = FontManager:CreateFontString(contentCard, "body", "OVERLAY")
        fs:SetPoint("TOPLEFT", contentCard, "TOPLEFT", UI_SPACING.SIDE_MARGIN + 2, -yOffset)
        fs:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -(UI_SPACING.SIDE_MARGIN + 2), -yOffset)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(true)
        fs:SetText(text)
        yOffset = yOffset + fs:GetStringHeight() + (spacing or 6)
        return fs
    end

    -- Two inks for the whole page: accent names the sections, gold names the people.
    local accent = { AccentRGB() }
    local gold = { SemanticGoldRGB() }

    --- Section headings: 16px base scaled to ~18. One step above the 14px card titles and
    --- clearly above 12px body, without shouting over the content the way ~22 did.
    local function AddSectionTitle(text)
        return AddText(text, "header", accent, 12, true, 1.15)
    end

    --- Feature list as a uniform grid of cards. Each entry carries the same atlas its tab uses,
    --- so the page reads as a map of the addon. Columns come from the width: one full-width
    --- column ran ~250 characters a line, a fixed narrow one wasted most of a wide screen.
    ---
    --- Two passes, because one card per content height produced a ragged patchwork. Pass one
    --- builds every card and measures its wrapped description; pass two gives them all the
    --- tallest height and lays them out row by row, so the grid lines up in both directions.
    local FEATURE_MIN_COL = 430
    local FEATURE_GAP = 16
    local CARD_PAD = 12
    local CARD_ICON = 24
    local CARD_TITLE_GAP = 8
    local function AddFeatureGrid(items)
        local side = UI_SPACING.SIDE_MARGIN + 2
        local usable = math.max(200, innerWidth - side * 2)
        local cols = math.floor(usable / FEATURE_MIN_COL)
        if cols < 1 then cols = 1 end
        if cols > 3 then cols = 3 end
        local colW = math.floor((usable - FEATURE_GAP * (cols - 1)) / cols)

        local cards = {}
        local tallestDesc = 0

        for i = 1, #items do
            local entry = items[i]
            local card = (ns.UI.Factory and ns.UI.Factory.CreateContainer)
                and ns.UI.Factory:CreateContainer(contentCard, colW, 80, true)
            if not card then
                card = CreateFrame("Frame", nil, contentCard)
                card:SetSize(colW, 80)
            end
            card:SetWidth(colW)

            local icon = card:CreateTexture(nil, "ARTWORK")
            icon:SetSize(CARD_ICON, CARD_ICON)
            icon:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -CARD_PAD)
            local atlas = entry.tab and ns.UI_GetTabIcon and ns.UI_GetTabIcon(entry.tab)
            if atlas then
                pcall(icon.SetAtlas, icon, atlas, false)
            end

            local title = FontManager:CreateFontString(card, "title", "OVERLAY")
            title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            title:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)
            title:SetJustifyH("LEFT")
            title:SetTextColor(accent[1], accent[2], accent[3])
            SetScaledFont(title, "title", 1)
            title:SetText(entry.title)

            local desc = FontManager:CreateFontString(card, "body", "OVERLAY")
            desc:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -(CARD_PAD + CARD_ICON + CARD_TITLE_GAP))
            -- Explicit width, not a TOPLEFT/TOPRIGHT pair: the card is still unanchored at this
            -- point, so a width derived from the parent resolves to nothing and GetStringHeight
            -- reports one unwrapped line. Every card then came out too short and clipped its text.
            desc:SetWidth(colW - CARD_PAD * 2)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(true)
            ns.UI_SetTextColorRole(desc, "Normal")
            desc:SetText(entry.desc)

            -- Height only settles once the text has a width and content to wrap.
            local h = desc:GetStringHeight() or 0
            if h > tallestDesc then tallestDesc = h end
            cards[#cards + 1] = card
        end

        local cardH = CARD_PAD + CARD_ICON + CARD_TITLE_GAP + tallestDesc + CARD_PAD
        for i = 1, #cards do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            cards[i]:SetHeight(cardH)
            cards[i]:SetPoint("TOPLEFT", contentCard, "TOPLEFT",
                side + col * (colW + FEATURE_GAP),
                -(yOffset + row * (cardH + FEATURE_GAP)))
            cards[i]:Show()
        end

        local rows = math.ceil(#cards / cols)
        if rows > 0 then
            yOffset = yOffset + rows * cardH + (rows - 1) * FEATURE_GAP
        end
    end


    -- HEADER
    AddText((ns.L and ns.L["WELCOME_TITLE"]) or "Welcome to Warband Nexus!", "header", accent, 4, true, 1.5)
    local versionText = ns.Constants and ns.Constants.ADDON_VERSION
    if versionText then
        local vfs = AddText("v" .. versionText, "small", nil, 0, true)
        ns.UI_SetTextColorRole(vfs, "Muted")
    end

    AddDivider()

    -- CREDITS
    AddSectionTitle((ns.L and ns.L["INFO_CREDITS_LORE_SUBTITLE"]) or "Special Thanks")
    AddText("Egzolinas the Loremaster!", "body", gold, 14, true)

    AddDivider()

    AddSectionTitle((ns.L and ns.L["CONTRIBUTORS_TITLE"]) or "Contributors")

    local CLASS_COLORS = ns.Constants and ns.Constants.CLASS_COLORS
    local colorEnd = "|r"
    local blizzGold = SemanticGoldHex()

    if CLASS_COLORS then
        AddRichLine(
            CLASS_COLORS.MAGE .. "Vidotrieth" .. colorEnd .. "  " ..
            CLASS_COLORS.DEMONHUNTER .. "Ragepull" .. colorEnd .. "  " ..
            CLASS_COLORS.WARRIOR .. "Mysticsong" .. colorEnd .. "  " ..
            CLASS_COLORS.HUNTER .. "Aztech" .. colorEnd,
            6
        )
    end

    AddRichLine(
        blizzGold .. "DivaDelirium" .. colorEnd .. "  " ..
        blizzGold .. "Jack the Dipper" .. colorEnd .. "  " ..
        blizzGold .. "Koralia91" .. colorEnd .. "  " ..
        blizzGold .. "nanjuekaien1" .. colorEnd .. "  " ..
        blizzGold .. "Nexus-Hub" .. colorEnd .. "  " ..
        blizzGold .. "huchang47" .. colorEnd,
        14
    )

    AddDivider()

    AddSectionTitle((ns.L and ns.L["ABOUT_PATREON_SUPPORTERS"]) or "Patreon Supporters")
    -- One line: two names stacked as separate paragraphs read as two groups, not two people.
    local supporters = {}
    supporters[#supporters + 1] = (ns.L and ns.L["ABOUT_PATREON_SUPPORTER_1"]) or "Melissa CD"
    supporters[#supporters + 1] = (ns.L and ns.L["ABOUT_PATREON_SUPPORTER_2"]) or "Bedroom"
    AddText(table.concat(supporters, "   "), "body", gold, 0, true)

    -- COMMUNITY LINKS
    -- Two icon buttons. The client cannot open a browser, so a click hands the address to the
    -- Factory's shared copy popup -- the same one Wowhead links use, so every link in the
    -- addon behaves identically. It parents to UIParent, so the surrounding scroll frame
    -- cannot clip it.
    local LINK_BTN_W = 152
    local LINK_BTN_H = 38
    local LINK_BTN_GAP = 12
    local LINK_ICON = 26
    local LINK_ICON_INSET = 12


    local CONST = ns.Constants or {}
    local LINK_URLS = CONST.LINKS or {}
    local LINK_LOGO = CONST.COMMUNITY_LOGO or {}
    local LINK_COLOR = CONST.COMMUNITY_COLOR or {}

    ---@param iconPath string|nil full-colour brand logo
    ---@param labelText string
    ---@param brandColor table|nil {r,g,b}
    ---@param tooltipText string
    ---@param url string|nil
    ---@return Button|nil
    local function CreateLinkButton(iconPath, labelText, brandColor, tooltipText, url)
        if not url or url == "" then return nil end
        local btn = ns.UI_CreateButton and ns.UI_CreateButton(contentCard, LINK_BTN_W, LINK_BTN_H)
        if not btn then
            btn = CreateFrame("Button", nil, contentCard)
        end
        btn:SetSize(LINK_BTN_W, LINK_BTN_H)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(LINK_ICON, LINK_ICON)
        icon:SetPoint("LEFT", btn, "LEFT", LINK_ICON_INSET, 0)
        icon:SetTexture(iconPath)
        icon:SetTexCoord(0, 1, 0, 1)
        -- Brand art, so no vertex tint and no desaturation: the WN_ICON_* monochrome path
        -- would flatten the Discord blurple and the Patreon gold into a single ink colour.
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1, 1)
        btn._wnLinkIcon = icon

        local label = FontManager:CreateFontString(btn, "title", "OVERLAY")
        label:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        -- Same weighted path the headings use, so the outline survives whatever the user set
        -- anti-aliasing to. Applied before SetText for consistency with the measured elements.
        SetScaledFont(label, "title", 1)
        label:SetText(labelText)
        if brandColor then
            label:SetTextColor(brandColor[1], brandColor[2], brandColor[3], 1)
        else
            ns.UI_SetTextColorRole(label, "Bright")
        end
        btn._wnLinkLabel = label

        local hint = (ns.L and ns.L["CLICK_TO_COPY_URL"]) or "Click to copy the link"
        btn:SetScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            local tr, tg, tb = 1, 1, 1
            if ns.UI_GetTooltipTitleColor then tr, tg, tb = ns.UI_GetTooltipTitleColor() end
            GameTooltip:SetText(tooltipText, tr, tg, tb)
            local dr, dg, db = 0.6, 0.6, 0.6
            if ns.UI_GetTooltipDescColor then dr, dg, db = ns.UI_GetTooltipDescColor() end
            GameTooltip:AddLine(hint, dr, dg, db)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function(selfBtn)
            if ns.UI.Factory and ns.UI.Factory.ShowCopyURL then
                ns.UI.Factory:ShowCopyURL(url, tooltipText, selfBtn)
            end
        end)
        return btn
    end

    local discordBtn = CreateLinkButton(LINK_LOGO.DISCORD, "Discord", LINK_COLOR.DISCORD,
        (ns.L and ns.L["DISCORD_TOOLTIP"]) or "Warband Nexus Discord", LINK_URLS.DISCORD)
    local patreonBtn = CreateLinkButton(LINK_LOGO.PATREON, "Patreon", LINK_COLOR.PATREON,
        (ns.L and ns.L["PATREON_TOOLTIP"]) or "Warband Nexus on Patreon", LINK_URLS.PATREON)

    -- Centre the pair on the card. Anchoring from the card's TOP keeps them centred at any
    -- width, since this content is repainted for both the tab and the standalone dialog.
    -- Top-right of the header band rather than a section of their own: two small links do
    -- not need a heading, a hint line and a divider. Anchored, not part of the vertical flow,
    -- so they never push the page down. Their tooltips still explain the copy step.
    if discordBtn or patreonBtn then
        local anchor = contentCard
        local right = -(UI_SPACING.SIDE_MARGIN + 2)
        if patreonBtn then
            patreonBtn:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", right, -(UI_SPACING.SCROLL_CONTENT_TOP_PADDING or 12))
            right = right - LINK_BTN_W - LINK_BTN_GAP
        end
        if discordBtn then
            discordBtn:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", right, -(UI_SPACING.SCROLL_CONTENT_TOP_PADDING or 12))
        end
    end

    AddDivider()

    -- FEATURES
    -- The old page nested "Features overview" over "AddOn Overview" over the list: three
    -- headings for one idea. The overview paragraph now sits straight under the section.
    AddSectionTitle((ns.L and ns.L["INFO_FEATURES_SECTION_TITLE"]) or "Features overview")
    AddLeadParagraph((ns.L and ns.L["ADDON_OVERVIEW_DESC"]) or "Warband Nexus provides a centralized interface for managing all your characters, currencies, reputations, items, and PvE progress across your entire Warband.", 20)

    AddFeatureGrid({
        { tab = "chars", title = (ns.L and ns.L["INFO_TAB_CHARACTERS"]) or "Characters", desc = (ns.L and ns.L["CHARACTERS_DESC"]) or "View all characters with gold, level, iLvl, faction, race, class, professions, keystone, and last played info. Track or untrack characters, mark favorites." },
        { tab = "storage", title = (ns.L and ns.L["INFO_TAB_STORAGE"]) or "Storage", desc = (ns.L and ns.L["STORAGE_DESC"]) or "Aggregated inventory view from all characters — bags, personal bank, and warband bank combined in one place." },
        { tab = "items", title = (ns.L and ns.L["INFO_TAB_ITEMS"]) or "Items", desc = (ns.L and ns.L["ITEMS_DESC"]) or "Search and browse items across all bags, banks, and warband bank. Auto-scans when you open a bank. Shows which characters own each item via tooltip." },
        { tab = "gear", title = (ns.L and ns.L["INFO_TAB_GEAR"]) or "Gear", desc = (ns.L and ns.L["GEAR_DESC"]) or "Equipped gear, upgrade options, storage recommendations, and cross-character upgrade candidates." },
        { tab = "currency", title = (ns.L and ns.L["INFO_TAB_CURRENCY"]) or "Currency", desc = (ns.L and ns.L["CURRENCY_DESC"]) or "View all currencies organized by expansion. Compare amounts across characters with hover tooltips. Hide empty currencies with one click." },
        { tab = "reputations", title = (ns.L and ns.L["INFO_TAB_REPUTATIONS"]) or "Reputations", desc = (ns.L and ns.L["REPUTATIONS_DESC"]) or "Compare reputation progress across all characters. Shows Account-Wide vs Character-Specific factions with hover tooltips for per-character breakdown." },
        { tab = "pve", title = (ns.L and ns.L["INFO_TAB_PVE"]) or "PvE", desc = (ns.L and ns.L["PVE_DESC"]) or "Track Great Vault progress with next-tier indicators, Mythic+ scores and keys, keystone affixes, dungeon history, and upgrade currency across all characters." },
        { tab = "pvp", title = (ns.L and ns.L["INFO_TAB_PVP"]) or "PvP", desc = (ns.L and ns.L["PVP_DESC"]) or "Compare rated brackets across your warband: 2v2, 3v3, Solo Shuffle, Blitz, and Rated BG ratings with weekly and seasonal win records. Tracks honor level, Honor and Conquest caps, recent match history with rating changes, and the active brawl." },
        { tab = "professions", title = (ns.L and ns.L["INFO_TAB_PROFESSIONS"]) or "Professions", desc = (ns.L and ns.L["PROFESSIONS_INFO_DESC"]) or "See every tracked character's crafting professions in one sortable grid: skill level, equipped tools, concentration and recharge, knowledge points, recipe coverage, and weekly knowledge progress. Data updates when you open each character's profession panel (default K). While a profession window stays open, Recipe Companion shows how many of each reagent you carry in bags." },
        { tab = "collections", title = (ns.L and ns.L["INFO_TAB_COLLECTIONS"]) or "Collections", desc = (ns.L and ns.L["COLLECTIONS_DESC"]) or "Overview of mounts, pets, toys, and other collectibles. Track collection progress and find missing items." },
        { tab = "plans", title = (ns.L and ns.L["INFO_TAB_PLANS"]) or "To-Do", desc = (ns.L and ns.L["PLANS_DESC"]) or "Track uncollected mounts, pets, toys, and achievements. Add goals, view drop sources, and monitor try counts. Access via /wn plan or minimap icon." },
        { tab = "stats", title = (ns.L and ns.L["INFO_TAB_STATISTICS"]) or "Statistics", desc = (ns.L and ns.L["STATISTICS_DESC"]) or "View achievement points, mount/pet/toy/illusion/title collection progress, unique pet count, and bag/bank usage statistics." },
    })

    AddDivider()

    local tgr, tgg, tgb = SemanticGreenRGB()
    AddText((ns.L and ns.L["THANK_YOU_MSG"]) or "Thank you for using Warband Nexus!", "title", { tgr, tgg, tgb }, 8, true)

    local lastText = FontManager:CreateFontString(contentCard, "body", "OVERLAY")
    lastText:SetPoint("TOPLEFT", contentCard, "TOPLEFT", UI_SPACING.SIDE_MARGIN + 2, -yOffset)
    lastText:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -(UI_SPACING.SIDE_MARGIN + 2), -yOffset)
    lastText:SetJustifyH("CENTER")
    lastText:SetText((ns.L and ns.L["REPORT_BUGS"]) or "Report bugs or share suggestions on CurseForge to help improve the addon.")
    ns.UI_SetTextColorRole(lastText, "Normal")
    lastText:SetWordWrap(true)
    yOffset = yOffset + lastText:GetStringHeight() + 20
    lastElement = lastText

    if opts.includeOkButton then
        local okBtn
        if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateButton then
            okBtn = ns.UI.Factory:CreateButton(contentCard, 120, 32)
        else
            okBtn = CreateFrame("Button", nil, contentCard)
            okBtn:SetSize(120, 32)
        end
        okBtn:SetPoint("CENTER", contentCard, "TOP", 0, -yOffset - 16)
        if ns.UI_ApplyVisuals then
            local okBg = ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop() or { COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], 1 }
            ns.UI_ApplyVisuals(okBtn, okBg, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
        end
        local okBtnText = FontManager:CreateFontString(okBtn, "body", "OVERLAY")
        okBtnText:SetPoint("CENTER")
        okBtnText:SetText((ns.L and ns.L["OK_BUTTON"]) or "OK")
        ns.UI_SetTextColorRole(okBtnText, "Bright")
        okBtn:SetScript("OnClick", function()
            if opts.onOk then opts.onOk() end
        end)
        yOffset = yOffset + 32 + 12
    end

    contentCard:SetHeight(yOffset)
    contentCard:Show()
    return yOffset
end

--- Main window About tab (credits, contributors, tab guide).
---@param parent Frame scroll child
---@return number content height
function WarbandNexus:DrawAboutTab(parent)
    if not parent then return 200 end
    local sideInset = 10
    local width = parent:GetWidth() or 600
    local effectiveWidth = math.max(240, width - sideInset * 2)
    local aboutHost = (ns.UI.Factory and ns.UI.Factory.CreateContainer)
        and ns.UI.Factory:CreateContainer(parent, effectiveWidth, 1, false)
    if not aboutHost then
        aboutHost = CreateFrame("Frame", nil, parent)
        aboutHost:SetSize(effectiveWidth, 1)
    end
    aboutHost:ClearAllPoints()
    aboutHost:SetPoint("TOPLEFT", parent, "TOPLEFT", sideInset, -12)
    aboutHost:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -sideInset, -12)
    aboutHost:SetWidth(effectiveWidth)
    local aboutH = 400
    if ns.UI_PaintAboutContent then
        aboutH = ns.UI_PaintAboutContent(aboutHost, effectiveWidth, nil) or aboutH
    end
    aboutHost:SetHeight(math.max(200, aboutH + 8))
    aboutHost:Show()
    return 12 + aboutHost:GetHeight() + 16
end

--- Legacy popup (optional); primary entry is the About main tab.
function WarbandNexus:ShowInfoDialog()
    local COLORS = ns.UI_COLORS or { accent = { 0.40, 0.20, 0.58, 1 }, accentDark = { 0.28, 0.14, 0.41, 1 }, border = { 0.20, 0.20, 0.25, 1 }, bg = { 0.06, 0.06, 0.08, 0.98 } }

    if self.infoDialog then
        self.infoDialog:Show()
        return
    end

    local Factory = ns.UI and ns.UI.Factory
    local dialog
    if Factory and Factory.CreateContainer then
        dialog = Factory:CreateContainer(UIParent, 650, 650, false, "WarbandNexusInfoDialog")
    end
    if not dialog then
        dialog = CreateFrame("Frame", "WarbandNexusInfoDialog", UIParent)
        dialog:SetSize(650, 650)
    end
    dialog:SetPoint("CENTER")
    dialog:EnableMouse(true)
    dialog:SetMovable(true)

    if ns.WindowManager then
        ns.WindowManager:ApplyStrata(dialog, ns.WindowManager.PRIORITY.POPUP)
        ns.WindowManager:Register(dialog, ns.WindowManager.PRIORITY.POPUP)
        ns.WindowManager:InstallESCHandler(dialog)
        ns.WindowManager:InstallDragHandler(dialog, dialog)
    else
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(200)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    end
    self.infoDialog = dialog

    if ns.UI_ApplyVisuals then
        local shell = GetDialogShellBg()
        ns.UI_ApplyVisuals(dialog, shell, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1 })
    end

    local infoMainShell = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    local infoChromeInset = infoMainShell.FRAME_CONTENT_INSET or 2
    local infoHeaderH = infoMainShell.INFO_DIALOG_HEADER_HEIGHT or 50

    local header
    if Factory and Factory.CreateContainer then
        header = Factory:CreateContainer(dialog, math.max(1, dialog:GetWidth() - infoChromeInset * 2), infoHeaderH, false)
    end
    if not header then
        header = CreateFrame("Frame", nil, dialog)
        header:SetHeight(infoHeaderH)
    end
    header:SetPoint("TOPLEFT", infoChromeInset, -infoChromeInset)
    header:SetFrameLevel(dialog:GetFrameLevel() + 10)

    if ns.UI_ApplyVisuals then
        local headerBg = COLORS.bgCard or COLORS.surfaceHeaderChrome or COLORS.bg
        ns.UI_ApplyVisuals(header, { headerBg[1], headerBg[2], headerBg[3], headerBg[4] or 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
    end

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(32, 32)
    logo:SetPoint("LEFT", header, "LEFT", 15, 0)
    logo:SetTexture(ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga")

    local title = FontManager:CreateFontString(header, FontManager:GetFontRole("tabTitlePrimary"), "OVERLAY")
    title:SetPoint("CENTER", header, "CENTER", 0, 0)
    title:SetText((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus")
    ns.UI_SetTextColorRole(title, "Bright")

    local closeBtn
    if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateButton then
        closeBtn = ns.UI.Factory:CreateButton(header, 28, 28)
    else
        closeBtn = CreateFrame("Button", nil, header)
        closeBtn:SetSize(28, 28)
    end
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -UI_SPACING.AFTER_ELEMENT, 0)
    if ns.UI_ApplyVisuals then
        local closeBg = ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop() or { COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 0.95 }
        ns.UI_ApplyVisuals(closeBtn, closeBg, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(18, 18)
    closeIcon:SetPoint("CENTER")
    if not ns.UI_SetMainChromeIcon(closeIcon, "close", { 0.9, 0.3, 0.3 }) then
        closeIcon:SetAtlas("uitools-icon-close")
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    end
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)

    local infoDlgScrollGap = UI_SPACING.SCROLL_CONTENT_TOP_PADDING or 12
    local infoScrollTopY = -(infoChromeInset + infoHeaderH + infoDlgScrollGap)
    local infoSbColTopInset = infoChromeInset + infoHeaderH + infoDlgScrollGap - 2
    local infoSbColW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
    local scrollFrame
    if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateScrollFrame then
        scrollFrame = ns.UI.Factory:CreateScrollFrame(dialog, "UIPanelScrollFrameTemplate", true)
    else
        scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    end
    scrollFrame:SetParent(dialog)
    scrollFrame:SetFrameLevel(dialog:GetFrameLevel() + 1)
    local infoSbLane = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve()) or (infoSbColW + 2)
    scrollFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, infoScrollTopY)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -(8 + infoSbLane), 8)

    if ns.UI.Factory and ns.UI.Factory.CreateBareScrollBarColumn and ns.UI.Factory.EnsureScrollBarColumnSync then
        local scrollBarColumn = ns.UI.Factory:CreateBareScrollBarColumn(dialog, infoSbColW)
        ns.UI.Factory:EnsureScrollBarColumnSync(scrollFrame, scrollBarColumn, { width = infoSbColW, gap = 2 })
    elseif ns.UI and ns.UI.Factory and ns.UI.Factory.CreateScrollBarColumn and ns.UI.Factory.PositionScrollBarInContainer then
        local scrollBarColumn = ns.UI.Factory:CreateScrollBarColumn(dialog, infoSbColW, 0, 0)
        if scrollFrame.ScrollBar then
            ns.UI.Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
        end
    end

    local scrollW = scrollFrame:GetWidth()
    if not scrollW or scrollW < 2 then
        scrollW = math.max(1, (dialog:GetWidth() or 650) - 60)
    end
    local scrollChild
    if Factory and Factory.CreateContainer then
        scrollChild = Factory:CreateContainer(scrollFrame, scrollW, 1, false)
    end
    if not scrollChild then
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
    end
    scrollChild:SetWidth(scrollW)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local contentH = ns.UI_PaintAboutContent(scrollChild, scrollW, {
        includeOkButton = true,
        onOk = function() dialog:Hide() end,
    })
    scrollChild:SetHeight(math.max(1, contentH))

    if ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
    end
    scrollFrame:SetVerticalScroll(0)
    scrollFrame:UpdateScrollChildRect()

    dialog:Show()
end
