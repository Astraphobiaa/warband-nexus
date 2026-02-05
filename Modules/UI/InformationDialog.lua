--[[
    Warband Nexus - Information Dialog
    Displays addon information, features, and usage instructions
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

--[[
    Show Information Dialog
    Displays addon information, features, and usage instructions
]]
function WarbandNexus:ShowInfoDialog()
    -- Get theme colors
    local COLORS = ns.UI_COLORS
    
    -- Create dialog frame (or reuse if exists)
    if self.infoDialog then
        self.infoDialog:Show()
        return
    end
    
    local dialog = CreateFrame("Frame", "WarbandNexusInfoDialog", UIParent)
    dialog:SetSize(650, 650)  -- Standard size for full content
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(1000)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    self.infoDialog = dialog
    
    -- Apply custom theme to main dialog
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(dialog, 
            {0.02, 0.02, 0.03, 0.98},  -- Dark background
            {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1}  -- Accent border
        )
    end
    
    -- Header frame (using Factory pattern)
    local header = ns.UI.Factory:CreateContainer(dialog)
    header:SetHeight(50)
    header:SetPoint("TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", -2, -2)
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
    local title = FontManager:CreateFontString(header, "header", "OVERLAY")
    title:SetPoint("CENTER", header, "CENTER", 0, 0)
    title:SetText("Warband Nexus")
    title:SetTextColor(1, 1, 1)  -- Always white
    
    -- Custom themed close button with Blizzard icon
    local closeBtn = ns.UI.Factory:CreateButton(header, 28, 28)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    
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
    
    -- Scroll Frame (using Factory pattern with modern scroll bar)
    -- Standard padding: 8px from dialog edges
    local scrollFrame = ns.UI.Factory:CreateScrollFrame(dialog, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetParent(dialog)
    scrollFrame:SetFrameLevel(dialog:GetFrameLevel() + 1)  -- Below header (header is +10)
    scrollFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -64)  -- 8px left, -64px top (50px header + 2px borders + 12px gap)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -30, 8)  -- Leave 30px for scroll bar (22px bar + 8px margin)
    
    -- Manually position scroll bar to align with header bottom
    if scrollFrame.ScrollBar then
        local scrollBar = scrollFrame.ScrollBar
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -8, -28)  -- Below scroll up button (16px button + 12px gap)
        scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -8, 16)  -- 16px above scroll frame bottom (for 16px button below)
        
        -- Position custom scroll buttons to align with header
        if scrollBar.ScrollUpBtn then
            scrollBar.ScrollUpBtn:ClearAllPoints()
            scrollBar.ScrollUpBtn:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -8, -12)  -- 12px gap below header
            scrollBar.ScrollUpBtn:SetFrameLevel(scrollBar:GetFrameLevel() + 5)  -- Above scroll bar
        end
        
        if scrollBar.ScrollDownBtn then
            scrollBar.ScrollDownBtn:ClearAllPoints()
            scrollBar.ScrollDownBtn:SetPoint("TOP", scrollBar, "BOTTOM", 0, 0)  -- NO GAP - directly attached
            scrollBar.ScrollDownBtn:SetFrameLevel(scrollBar:GetFrameLevel() + 5)  -- Above scroll bar
        end
    end
    
    local scrollChild = ns.UI.Factory:CreateContainer(scrollFrame)
    -- Width matches scroll frame (no extra padding needed)
    scrollChild:SetSize(scrollFrame:GetWidth() or 590, 1) -- Height will be set dynamically
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Content card (everything inside a bordered card)
    -- NO PADDING - card fills scrollChild completely for symmetry
    local contentCard = ns.UI_CreateCard(scrollChild, 100)  -- Initial height (will be set dynamically)
    contentCard:SetPoint("TOPLEFT", 0, 0)
    contentCard:SetPoint("TOPRIGHT", 0, 0)
    
    local yOffset = 12  -- Start with padding inside card (reduced from 15 to 12)
    local lastElement = nil  -- Track last created element for card bottom anchor
    
    local function AddText(text, fontType, color, spacing, centered)
        -- Map font types: "header", "title", "subtitle", "body", "small"
        local fs = FontManager:CreateFontString(contentCard, fontType or "body", "OVERLAY")
        fs:SetPoint("TOPLEFT", contentCard, "TOPLEFT", 12, -yOffset)
        fs:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -12, -yOffset)
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
    
    AddText("Welcome to Warband Nexus!", "header", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 12, true)
    
    -- AddOn Summary
    AddText("AddOn Overview", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 6)
    AddText("Warband Nexus provides a centralized interface for managing all your characters, currencies, reputations, items, and PvE progress across your entire Warband.", "body", {0.9, 0.9, 0.9}, 18)
    
    -- Tab Descriptions
    AddText("Characters", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText("View all your characters with gold, level, professions, and last played info.", "body", {0.9, 0.9, 0.9}, 10)
    
    AddText("Items", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText("Search items across all bags and banks. Auto-updates when you open the bank.", "body", {0.9, 0.9, 0.9}, 10)
    
    AddText("Storage", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText("Browse your entire inventory aggregated from all characters and banks.", "body", {0.9, 0.9, 0.9}, 10)
    
    AddText("PvE", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText("Track Great Vault, Mythic+ keystones, and raid lockouts for all characters.", "body", {0.9, 0.9, 0.9}, 10)
    
    AddText("Reputations", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText("Monitor reputation progress with smart filtering (Account-Wide vs Character-Specific).", "body", {0.9, 0.9, 0.9}, 10)
    
    AddText("Currency", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText("View all currencies organized by expansion with filtering options.", "body", {0.9, 0.9, 0.9}, 10)
    
    AddText("Plans", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText("Browse and track mounts, pets, toys, achievements, and transmogs you haven't collected yet.", "body", {0.9, 0.9, 0.9}, 10)
    
    AddText("Statistics", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText("View achievement points, collection progress, and bag/bank usage stats.", "body", {0.9, 0.9, 0.9}, 25)
    
    -- Special Thanks
    AddText("Special Thanks", "title", {1, 0.84, 0}, 8, true)
    AddText("Egzolinas the Loremaster!", "body", {0.96, 0.55, 0.73}, 20, true)  -- Paladin color (F58CBA)
    
    -- Supporters (with class colors)
    AddText("Supporters", "title", {0.4, 0.8, 1}, 8, true)
    
    -- Create colored supporter list (using centralized class colors from Constants)
    local supporterText = FontManager:CreateFontString(contentCard, "body", "OVERLAY")
    supporterText:SetPoint("TOPLEFT", contentCard, "TOPLEFT", 12, -yOffset)
    supporterText:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -12, -yOffset)
    supporterText:SetJustifyH("CENTER")
    supporterText:SetWordWrap(true)
    
    -- Get class colors from Constants
    local CLASS_COLORS = ns.Constants.CLASS_COLORS
    local colorWhite = "|cffFFFFFF"
    local colorEnd = "|r"
    
    supporterText:SetText(
        colorWhite .. "Zehel_Fenris" .. colorEnd .. " • " ..
        colorWhite .. "huchang47" .. colorEnd .. " • " ..
        CLASS_COLORS.DEMONHUNTER .. "Ragepull" .. colorEnd .. " • " ..
        CLASS_COLORS.MAGE .. "Vidotrieth" .. colorEnd .. " • " ..
        CLASS_COLORS.WARRIOR .. "MysticSong" .. colorEnd
    )
    
    yOffset = yOffset + supporterText:GetStringHeight() + 20
    lastElement = supporterText
    
    -- Footer (NO DIVIDER - just centered text)
    AddText("Thank you for using Warband Nexus!", "title", {0.2, 0.8, 0.2}, 8, true)
    
    -- FINAL TEXT: This should be the LAST element
    local lastText = FontManager:CreateFontString(contentCard, "body", "OVERLAY")
    lastText:SetPoint("TOPLEFT", contentCard, "TOPLEFT", 12, -yOffset)
    lastText:SetPoint("TOPRIGHT", contentCard, "TOPRIGHT", -12, -yOffset)
    lastText:SetJustifyH("CENTER")
    lastText:SetText("Report bugs or share suggestions on CurseForge to help improve the addon.")
    lastText:SetTextColor(0.8, 0.8, 0.8)
    lastText:SetWordWrap(true)
    
    yOffset = yOffset + lastText:GetStringHeight() + 20  -- 20px spacing before button
    lastElement = lastText
    
    -- OK Button (inside content flow) - Dark theme with border
    local okBtn = ns.UI.Factory:CreateButton(contentCard, 120, 32)
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
    okBtnText:SetText("OK")
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

