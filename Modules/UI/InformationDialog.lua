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

    local contentCard = ns.UI_CreateCard(parent, 100)
    contentCard:SetPoint("TOPLEFT", 0, 0)
    contentCard:SetPoint("TOPRIGHT", 0, 0)
    contentCard:SetWidth(innerWidth)

    local yOffset = UI_SPACING.SCROLL_CONTENT_TOP_PADDING or 12
    local lastElement

    local function AddText(text, fontType, color, spacing, centered)
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
        fs:SetText(text)
        yOffset = yOffset + fs:GetStringHeight() + (spacing or 12)
        lastElement = fs
        return fs
    end

    AddText((ns.L and ns.L["WELCOME_TITLE"]) or "Welcome to Warband Nexus!", "header", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 12, true)

    local sgR, sgG, sgB = SemanticGoldRGB()
    AddText((ns.L and ns.L["INFO_CREDITS_SECTION_TITLE"]) or "Credits & thanks", "title", { sgR, sgG, sgB }, 10, true)
    local ar, ag, ab = AccentRGB()
    AddText((ns.L and ns.L["INFO_CREDITS_LORE_SUBTITLE"]) or "Special Thanks", "title", { ar * 0.85 + 0.15, ag * 0.85 + 0.15, math.min(1, ab * 0.85 + 0.2) }, 6, true)
    AddText("Egzolinas the Loremaster!", "body", { 0.96, 0.55, 0.73 }, 14, true)

    AddText((ns.L and ns.L["CONTRIBUTORS_TITLE"]) or "Contributors", "title", { ar, ag, ab }, 6, true)

    local CLASS_COLORS = ns.Constants and ns.Constants.CLASS_COLORS
    local colorEnd = "|r"
    local blizzGold = SemanticGoldHex()

    if CLASS_COLORS then
        local contribClassLine = FontManager:CreateFontString(contentCard, "body", "OVERLAY")
        contribClassLine:SetPoint("TOPLEFT", contentCard, "TOPLEFT", UI_SPACING.SIDE_MARGIN + 2, -yOffset)
        contribClassLine:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -(UI_SPACING.SIDE_MARGIN + 2), -yOffset)
        contribClassLine:SetJustifyH("CENTER")
        contribClassLine:SetWordWrap(true)
        contribClassLine:SetText(
            CLASS_COLORS.MAGE .. "Vidotrieth" .. colorEnd .. "  " ..
            CLASS_COLORS.DEMONHUNTER .. "Ragepull" .. colorEnd .. "  " ..
            CLASS_COLORS.WARRIOR .. "Mysticsong" .. colorEnd .. "  " ..
            CLASS_COLORS.HUNTER .. "Aztech" .. colorEnd
        )
        yOffset = yOffset + contribClassLine:GetStringHeight() + 6
        lastElement = contribClassLine
    end

    local contribGoldLine = FontManager:CreateFontString(contentCard, "body", "OVERLAY")
    contribGoldLine:SetPoint("TOPLEFT", contentCard, "TOPLEFT", UI_SPACING.SIDE_MARGIN + 2, -yOffset)
    contribGoldLine:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -(UI_SPACING.SIDE_MARGIN + 2), -yOffset)
    contribGoldLine:SetJustifyH("CENTER")
    contribGoldLine:SetWordWrap(true)
    contribGoldLine:SetText(
        blizzGold .. "DivaDelirium" .. colorEnd .. "  " ..
        blizzGold .. "Jack the Dipper" .. colorEnd .. "  " ..
        blizzGold .. "Koralia91" .. colorEnd .. "  " ..
        blizzGold .. "nanjuekaien1" .. colorEnd .. "  " ..
        blizzGold .. "Nexus-Hub" .. colorEnd .. "  " ..
        blizzGold .. "huchang47" .. colorEnd
    )
    yOffset = yOffset + contribGoldLine:GetStringHeight() + 20
    lastElement = contribGoldLine

    AddText((ns.L and ns.L["ABOUT_PATREON_SUPPORTERS"]) or "Patreon Supporters", "title", { ar, ag, ab }, 6, true)
    local patreonR, patreonG, patreonB = SemanticGoldRGB()
    AddText((ns.L and ns.L["ABOUT_PATREON_SUPPORTER_1"]) or "Melissa CD", "body", { patreonR, patreonG, patreonB }, 20, true)

    AddText((ns.L and ns.L["INFO_FEATURES_SECTION_TITLE"]) or "Features overview", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 14, true)
    AddText((ns.L and ns.L["ADDON_OVERVIEW_TITLE"]) or "AddOn Overview", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 6)
    AddText((ns.L and ns.L["ADDON_OVERVIEW_DESC"]) or "Warband Nexus provides a centralized interface for managing all your characters, currencies, reputations, items, and PvE progress across your entire Warband.", "body", nil, 18)

    AddText((ns.L and ns.L["INFO_TAB_CHARACTERS"]) or "Characters", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["CHARACTERS_DESC"]) or "View all characters with gold, level, iLvl, faction, race, class, professions, keystone, and last played info. Track or untrack characters, mark favorites.", "body", nil, 10)

    AddText((ns.L and ns.L["INFO_TAB_STORAGE"]) or "Storage", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["STORAGE_DESC"]) or "Aggregated inventory view from all characters — bags, personal bank, and warband bank combined in one place.", "body", nil, 10)

    AddText((ns.L and ns.L["INFO_TAB_ITEMS"]) or "Items", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["ITEMS_DESC"]) or "Search and browse items across all bags, banks, and warband bank. Auto-scans when you open a bank. Shows which characters own each item via tooltip.", "body", nil, 10)

    AddText((ns.L and ns.L["INFO_TAB_GEAR"]) or "Gear", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["GEAR_DESC"]) or "Equipped gear, upgrade options, storage recommendations, and cross-character upgrade candidates.", "body", nil, 10)

    AddText((ns.L and ns.L["INFO_TAB_CURRENCY"]) or "Currency", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["CURRENCY_DESC"]) or "View all currencies organized by expansion. Compare amounts across characters with hover tooltips. Hide empty currencies with one click.", "body", nil, 10)

    AddText((ns.L and ns.L["INFO_TAB_REPUTATIONS"]) or "Reputations", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["REPUTATIONS_DESC"]) or "Compare reputation progress across all characters. Shows Account-Wide vs Character-Specific factions with hover tooltips for per-character breakdown.", "body", nil, 10)

    AddText((ns.L and ns.L["INFO_TAB_PVE"]) or "PvE", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["PVE_DESC"]) or "Track Great Vault progress with next-tier indicators, Mythic+ scores and keys, keystone affixes, dungeon history, and upgrade currency across all characters.", "body", nil, 10)

    AddText((ns.L and ns.L["INFO_TAB_PROFESSIONS"]) or "Professions", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["PROFESSIONS_INFO_DESC"]) or "See every tracked character's crafting professions in one sortable grid: skill level, equipped tools, concentration and recharge, knowledge points, recipe coverage, and weekly knowledge progress. Data updates when you open each character's profession panel (default K). While a profession window stays open, Recipe Companion shows how many of each reagent you carry in bags.", "body", nil, 10)

    AddText((ns.L and ns.L["INFO_TAB_COLLECTIONS"]) or "Collections", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["COLLECTIONS_DESC"]) or "Overview of mounts, pets, toys, and other collectibles. Track collection progress and find missing items.", "body", nil, 10)

    AddText((ns.L and ns.L["INFO_TAB_PLANS"]) or "To-Do", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["PLANS_DESC"]) or "Track uncollected mounts, pets, toys, and achievements. Add goals, view drop sources, and monitor try counts. Access via /wn plan or minimap icon.", "body", nil, 10)

    AddText((ns.L and ns.L["INFO_TAB_STATISTICS"]) or "Statistics", "title", { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }, 5)
    AddText((ns.L and ns.L["STATISTICS_DESC"]) or "View achievement points, mount/pet/toy/illusion/title collection progress, unique pet count, and bag/bank usage statistics.", "body", nil, 25)

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
