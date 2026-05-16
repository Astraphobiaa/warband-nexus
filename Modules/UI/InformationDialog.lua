--[[
    Warband Nexus - Information Dialog
    Displays addon information, features, and usage instructions
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management
local UI_SPACING = ns.UI_SPACING  -- Standardized spacing constants

--[[
    Show Information Dialog
    Displays addon information, features, and usage instructions
]]
function WarbandNexus:ShowInfoDialog()
    -- Get theme colors
    local COLORS = ns.UI_COLORS or {accent = {0.40, 0.20, 0.58, 1}, accentDark = {0.28, 0.14, 0.41, 1}, border = {0.20, 0.20, 0.25, 1}, bg = {0.06, 0.06, 0.08, 0.98}}
    
    -- Create dialog frame (or reuse if exists)
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

    -- WindowManager: standardized strata/level + ESC + combat hide
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
    
    -- Apply custom theme to main dialog
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(dialog, 
            {0.02, 0.02, 0.03, 0.98},  -- Dark background
            {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1}  -- Accent border
        )
    end
    
    local infoMainShell = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    local infoChromeInset = infoMainShell.FRAME_CONTENT_INSET or 2
    local infoHeaderH = infoMainShell.INFO_DIALOG_HEADER_HEIGHT or 50

    -- Header strip (Factory shell — fixed width matches dialog; dialog size is not user-resized)
    local header
    if Factory and Factory.CreateContainer then
        header = Factory:CreateContainer(dialog, math.max(1, dialog:GetWidth() - infoChromeInset * 2), infoHeaderH, false)
    end
    if not header then
        header = CreateFrame("Frame", nil, dialog)
        header:SetHeight(infoHeaderH)
    end
    header:SetPoint("TOPLEFT", infoChromeInset, -infoChromeInset)
    header:SetFrameLevel(dialog:GetFrameLevel() + 10)  -- Ensure header is above scroll frame
    
    -- Apply custom theme to header
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(header,
            {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1},  -- Accent dark bg
            {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}  -- Accent border
        )
    end
    
    -- Logo
    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(32, 32)
    logo:SetPoint("LEFT", header, "LEFT", 15, 0)
    logo:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")
    
    -- Title (centered) (WHITE - never changes with theme)
    local title = FontManager:CreateFontString(header, FontManager:GetFontRole("tabTitlePrimary"), "OVERLAY")
    title:SetPoint("CENTER", header, "CENTER", 0, 0)
    title:SetText((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus")
    title:SetTextColor(1, 1, 1)  -- Always white
    
    -- Custom themed close button with Blizzard icon
    local closeBtn
    if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateButton then
        closeBtn = ns.UI.Factory:CreateButton(header, 28, 28)
    else
        closeBtn = CreateFrame("Button", nil, header)
        closeBtn:SetSize(28, 28)
    end
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -UI_SPACING.AFTER_ELEMENT, 0)
    
    -- Apply custom theme to close button
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(closeBtn,
            {COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 0.95},  -- Dark background
            {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}  -- Accent border
        )
    end
    
    -- Use Blizzard's close icon
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)
    closeBtn:SetScript("OnEnter", function(self)
        closeIcon:SetVertexColor(1, 0.1, 0.1)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self,
                {COLORS.red[1], COLORS.red[2], COLORS.red[3], 0.95},
                {COLORS.red[1], COLORS.red[2], COLORS.red[3], 0.8}
            )
        end
    end)
    closeBtn:SetScript("OnLeave", function(self)
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self,
                {COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 0.95},
                {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
            )
        end
    end)
    
    -- Scroll Frame (Collections pattern: bar column + PositionScrollBarInContainer)
    -- Horizontal 8 keeps legacy content gutter; vertical follows `MAIN_SHELL` header + gap under header band.
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
    scrollFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, infoScrollTopY)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -(infoSbColW + 8), 8)

    -- Bar column: ~2px above scroll top (legacy shim), symmetric bottom inset for thumb buttons.
    if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateScrollBarColumn and ns.UI.Factory.PositionScrollBarInContainer then
        local scrollBarColumn = ns.UI.Factory:CreateScrollBarColumn(dialog, infoSbColW, infoSbColTopInset, 24)
        if scrollFrame.ScrollBar then
            ns.UI.Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
        end
    end

    local scrollChild
    local scrollW = scrollFrame:GetWidth()
    if not scrollW or scrollW < 2 then
        scrollW = math.max(1, (dialog:GetWidth() or 650) - 60)
    end
    if Factory and Factory.CreateContainer then
        scrollChild = Factory:CreateContainer(scrollFrame, scrollW, 1, false)
    end
    if not scrollChild then
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
    end
    scrollChild:SetWidth(scrollW)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Content card (everything inside a bordered card)
    -- NO PADDING - card fills scrollChild completely for symmetry
    local contentCard = ns.UI_CreateCard(scrollChild, 100)  -- Initial height (will be set dynamically)
    contentCard:SetPoint("TOPLEFT", 0, 0)
    contentCard:SetPoint("TOPRIGHT", 0, 0)
    
    local yOffset = UI_SPACING.SCROLL_CONTENT_TOP_PADDING  -- Start with padding inside card
    local lastElement = nil  -- Track last created element for card bottom anchor
    
    local function AddText(text, fontType, color, spacing, centered)
        -- Map font types: "header", "title", "subtitle", "body", "small"
        local fs = FontManager:CreateFontString(contentCard, fontType or "body", "OVERLAY")
        fs:SetPoint("TOPLEFT", contentCard, "TOPLEFT", UI_SPACING.SIDE_MARGIN + 2, -yOffset)
        fs:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -(UI_SPACING.SIDE_MARGIN + 2), -yOffset)
        fs:SetJustifyH(centered and "CENTER" or "LEFT")
        fs:SetWordWrap(true)
        if color then
            fs:SetTextColor(color[1], color[2], color[3])
        end
        fs:SetText(text)
        yOffset = yOffset + fs:GetStringHeight() + (spacing or 12)
        lastElement = fs  -- Track this as last element
        return fs
    end
    
    AddText((ns.L and ns.L["WELCOME_TITLE"]) or "Welcome to Warband Nexus!", "header", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 12, true)

    -- Credits up front so supporters / contributors are visible without scrolling past the full feature list
    AddText((ns.L and ns.L["INFO_CREDITS_SECTION_TITLE"]) or "Credits & thanks", "title", {1, 0.84, 0}, 10, true)

    -- Same visual tier as Contributors (title + cyan)
    AddText((ns.L and ns.L["INFO_CREDITS_LORE_SUBTITLE"]) or "Special Thanks", "title", {0.4, 0.8, 1}, 6, true)
    AddText("Egzolinas the Loremaster!", "body", {0.96, 0.55, 0.73}, 14, true)  -- Paladin color (F58CBA)

    AddText((ns.L and ns.L["CONTRIBUTORS_TITLE"]) or "Contributors", "title", {0.4, 0.8, 1}, 6, true)

    -- Class-colored names first; Blizzard gold (|cffffd100) on the line below for non-class styling
    local CLASS_COLORS = ns.Constants.CLASS_COLORS
    local colorEnd = "|r"
    local blizzGold = "|cffffd100"

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

    AddText((ns.L and ns.L["INFO_FEATURES_SECTION_TITLE"]) or "Features overview", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 14, true)
    
    -- AddOn Summary
    AddText((ns.L and ns.L["ADDON_OVERVIEW_TITLE"]) or "AddOn Overview", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 6)
    AddText((ns.L and ns.L["ADDON_OVERVIEW_DESC"]) or "Warband Nexus provides a centralized interface for managing all your characters, currencies, reputations, items, and PvE progress across your entire Warband.", "body", {0.9, 0.9, 0.9}, 18)
    
    -- Tab descriptions (same order as main window nav: Characters → Storage → Items → Gear → …)
    AddText((ns.L and ns.L["INFO_TAB_CHARACTERS"]) or "Characters", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["CHARACTERS_DESC"]) or "View all characters with gold, level, iLvl, faction, race, class, professions, keystone, and last played info. Track or untrack characters, mark favorites.", "body", {0.9, 0.9, 0.9}, 10)

    AddText((ns.L and ns.L["INFO_TAB_STORAGE"]) or "Storage", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["STORAGE_DESC"]) or "Aggregated inventory view from all characters — bags, personal bank, and warband bank combined in one place.", "body", {0.9, 0.9, 0.9}, 10)

    AddText((ns.L and ns.L["INFO_TAB_ITEMS"]) or "Items", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["ITEMS_DESC"]) or "Search and browse items across all bags, banks, and warband bank. Auto-scans when you open a bank. Shows which characters own each item via tooltip.", "body", {0.9, 0.9, 0.9}, 10)

    AddText((ns.L and ns.L["INFO_TAB_GEAR"]) or "Gear", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["GEAR_DESC"]) or "Equipped gear, upgrade options, storage recommendations, and cross-character upgrade candidates.", "body", {0.9, 0.9, 0.9}, 10)

    AddText((ns.L and ns.L["INFO_TAB_CURRENCY"]) or "Currency", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["CURRENCY_DESC"]) or "View all currencies organized by expansion. Compare amounts across characters with hover tooltips. Hide empty currencies with one click.", "body", {0.9, 0.9, 0.9}, 10)

    AddText((ns.L and ns.L["INFO_TAB_REPUTATIONS"]) or "Reputations", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["REPUTATIONS_DESC"]) or "Compare reputation progress across all characters. Shows Account-Wide vs Character-Specific factions with hover tooltips for per-character breakdown.", "body", {0.9, 0.9, 0.9}, 10)

    AddText((ns.L and ns.L["INFO_TAB_PVE"]) or "PvE", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["PVE_DESC"]) or "Track Great Vault progress with next-tier indicators, Mythic+ scores and keys, keystone affixes, dungeon history, and upgrade currency across all characters.", "body", {0.9, 0.9, 0.9}, 10)

    AddText((ns.L and ns.L["INFO_TAB_PROFESSIONS"]) or "Professions", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["PROFESSIONS_INFO_DESC"]) or "See every tracked character's crafting professions in one sortable grid: skill level, equipped tools, concentration and recharge, knowledge points, recipe coverage, and weekly knowledge progress. Data updates when you open each character's profession panel (default K). While a profession window stays open, Recipe Companion shows how many of each reagent you carry in bags.", "body", {0.9, 0.9, 0.9}, 10)

    AddText((ns.L and ns.L["INFO_TAB_COLLECTIONS"]) or "Collections", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["COLLECTIONS_DESC"]) or "Overview of mounts, pets, toys, transmog, and other collectibles. Track collection progress and find missing items.", "body", {0.9, 0.9, 0.9}, 10)

    AddText((ns.L and ns.L["INFO_TAB_PLANS"]) or "To-Do", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["PLANS_DESC"]) or "Track uncollected mounts, pets, toys, achievements, and transmogs. Add goals, view drop sources, and monitor try counts. Access via /wn plan or minimap icon.", "body", {0.9, 0.9, 0.9}, 10)

    AddText((ns.L and ns.L["INFO_TAB_STATISTICS"]) or "Statistics", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText((ns.L and ns.L["STATISTICS_DESC"]) or "View achievement points, mount/pet/toy/illusion/title collection progress, unique pet count, and bag/bank usage statistics.", "body", {0.9, 0.9, 0.9}, 25)
    
    -- Footer
    AddText((ns.L and ns.L["THANK_YOU_MSG"]) or "Thank you for using Warband Nexus!", "title", {0.2, 0.8, 0.2}, 8, true)
    
    -- FINAL TEXT: This should be the LAST element
    local lastText = FontManager:CreateFontString(contentCard, "body", "OVERLAY")
    lastText:SetPoint("TOPLEFT", contentCard, "TOPLEFT", UI_SPACING.SIDE_MARGIN + 2, -yOffset)
    lastText:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -(UI_SPACING.SIDE_MARGIN + 2), -yOffset)
    lastText:SetJustifyH("CENTER")
    lastText:SetText((ns.L and ns.L["REPORT_BUGS"]) or "Report bugs or share suggestions on CurseForge to help improve the addon.")
    lastText:SetTextColor(0.8, 0.8, 0.8)
    lastText:SetWordWrap(true)
    
    yOffset = yOffset + lastText:GetStringHeight() + 20  -- 20px spacing before button
    lastElement = lastText
    
    -- OK Button (inside content flow) - Dark theme with border
    local okBtn
    if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateButton then
        okBtn = ns.UI.Factory:CreateButton(contentCard, 120, 32)
    else
        okBtn = CreateFrame("Button", nil, contentCard)
        okBtn:SetSize(120, 32)
    end
    okBtn:SetPoint("CENTER", contentCard, "TOP", 0, -yOffset - 16)  -- yOffset + half button height
    
    -- Apply dark theme to OK button (black with accent border)
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(okBtn,
            {0.08, 0.08, 0.10, 1},  -- Dark background (almost black)
            {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}  -- Accent border
        )
    end
    
    -- OK button text
    local okBtnText = FontManager:CreateFontString(okBtn, "body", "OVERLAY")
    okBtnText:SetPoint("CENTER")
    okBtnText:SetText((ns.L and ns.L["OK_BUTTON"]) or "OK")
    okBtnText:SetTextColor(1, 1, 1)
    
    okBtn:SetScript("OnClick", function() dialog:Hide() end)
    okBtn:SetScript("OnEnter", function(self)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self,
                {0.12, 0.12, 0.14, 1},  -- Lighter dark on hover
                {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1}  -- Brighter border
            )
        end
    end)
    okBtn:SetScript("OnLeave", function(self)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self,
                {0.08, 0.08, 0.10, 1},  -- Dark background
                {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}  -- Accent border
            )
        end
    end)
    
    -- Update yOffset to include button
    yOffset = yOffset + 32 + 12  -- 32px button height + 12px bottom padding
    
    -- Set card height dynamically based on content (yOffset includes all content + button + padding)
    contentCard:SetHeight(yOffset)
    contentCard:Show()  -- CRITICAL: Show the card!
    
    -- Set scrollChild height to match card exactly
    scrollChild:SetHeight(yOffset)
    
    -- Update scroll bar visibility (hide if content fits)
    if ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
    end
    
    -- Reset scroll position
    scrollFrame:SetVerticalScroll(0)
    scrollFrame:UpdateScrollChildRect()
    
    C_Timer.After(0, function()
        if scrollFrame and scrollFrame:IsShown() then
            scrollFrame:SetVerticalScroll(0)
        end
    end)
    
    dialog:Show()
end

