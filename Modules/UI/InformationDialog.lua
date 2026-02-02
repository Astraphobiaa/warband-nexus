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
    dialog:SetSize(650, 650)  -- Optimized size: 650x650 for better content visibility
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
    
    -- Scroll Frame (using Factory pattern)
    local scrollFrame = ns.UI.Factory:CreateScrollFrame(dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetParent(dialog)
    scrollFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 15, -60)  -- Below header, inside dialog border
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -25, 47)  -- EXACT: OK button (32px) + bottom margin (15px) = 47px
    
    local scrollChild = ns.UI.Factory:CreateContainer(scrollFrame)
    scrollChild:SetSize(580, 1) -- Width adjusted for scroll bar space, height will be calculated dynamically
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Content
    local yOffset = 0
    local function AddText(text, fontType, color, spacing, centered)
        -- Map font types: "header", "title", "subtitle", "body", "small"
        local fs = FontManager:CreateFontString(scrollChild, fontType or "body", "OVERLAY")
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset)
        fs:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, -yOffset)
        fs:SetJustifyH(centered and "CENTER" or "LEFT")
        fs:SetWordWrap(true)
        if color then
            fs:SetTextColor(color[1], color[2], color[3])
        end
        fs:SetText(text)
        yOffset = yOffset + fs:GetStringHeight() + (spacing or 12)
        return fs
    end
    
    local function AddDivider()
        local line = scrollChild:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", scrollChild, "LEFT", 10, -yOffset)
        line:SetPoint("RIGHT", scrollChild, "RIGHT", -10, -yOffset)
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        yOffset = yOffset + 12  -- Reduced from 15 to 12
    end
    
    AddText("Welcome to Warband Nexus!", "header", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 6, true)
    
    -- AddOn Summary
    AddText("AddOn Overview", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 5)
    AddText("Warband Nexus provides a centralized interface for managing all your characters, currencies, reputations, items, and PvE progress across your entire Warband.", "body", {0.9, 0.9, 0.9}, 10)
    
    AddDivider()
    
    -- Tab Descriptions
    AddText("Characters", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 4)
    AddText("View all your characters with gold, level, professions, and last played info.", "body", {0.9, 0.9, 0.9}, 8)
    
    AddText("Items", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 4)
    AddText("Search items across all bags and banks. Auto-updates when you open the bank.", "body", {0.9, 0.9, 0.9}, 8)
    
    AddText("Storage", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 4)
    AddText("Browse your entire inventory aggregated from all characters and banks.", "body", {0.9, 0.9, 0.9}, 8)
    
    AddText("PvE", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 4)
    AddText("Track Great Vault, Mythic+ keystones, and raid lockouts for all characters.", "body", {0.9, 0.9, 0.9}, 8)
    
    AddText("Reputations", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 4)
    AddText("Monitor reputation progress with smart filtering (Account-Wide vs Character-Specific).", "body", {0.9, 0.9, 0.9}, 8)
    
    AddText("Currency", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 4)
    AddText("View all currencies organized by expansion with filtering options.", "body", {0.9, 0.9, 0.9}, 8)
    
    AddText("Plans", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 4)
    AddText("Browse and track mounts, pets, toys, achievements, and transmogs you haven't collected yet.", "body", {0.9, 0.9, 0.9}, 8)
    
    AddText("Statistics", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 4)
    AddText("View achievement points, collection progress, and bag/bank usage stats.", "body", {0.9, 0.9, 0.9}, 12)
    
    AddDivider()
    
    -- Special Thanks
    AddText("Special Thanks", "title", {1, 0.84, 0}, 6, true)
    AddText("Egzolinas the Loremaster!", "body", {0.96, 0.55, 0.73}, 15, true)  -- Paladin color (F58CBA)
    
    -- Supporters (with class colors)
    AddText("Supporters", "title", {0.4, 0.8, 1}, 6, true)
    
    -- Create colored supporter list (using centralized class colors from Constants)
    local supporterText = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
    supporterText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset)
    supporterText:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, -yOffset)
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
    
    yOffset = yOffset + supporterText:GetStringHeight() + 15
    
    -- Footer (NO DIVIDER BEFORE FOOTER - EVERYTHING CENTERED)
    AddText("Thank you for using Warband Nexus!", "title", {0.2, 0.8, 0.2}, 5, true)
    
    -- FINAL TEXT: This should be the LAST element before OK button
    local lastText = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
    lastText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset)
    lastText:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, -yOffset)
    lastText:SetJustifyH("CENTER")
    lastText:SetText("Report bugs or share suggestions on CurseForge to help improve the addon.")
    lastText:SetTextColor(0.8, 0.8, 0.8)
    lastText:SetWordWrap(true)
    
    yOffset = yOffset + lastText:GetStringHeight()
    
    -- Calculate scroll frame's EXACT available height
    local dialogHeight = 650  -- Dialog height (from SetSize)
    local headerHeight = 50   -- Header height
    local topMargin = 60      -- Top margin (from TOPLEFT anchor: -60)
    local bottomMargin = 47   -- Bottom margin (from BOTTOMRIGHT anchor: 47)
    
    -- Available height = dialog height - header - top margin - bottom margin
    local scrollFrameHeight = dialogHeight - headerHeight - (topMargin - headerHeight) - bottomMargin
    -- scrollFrameHeight = 650 - 50 - 10 - 47 = 543px
    
    -- CRITICAL: Use scroll frame's exact available height to prevent bottom gap
    -- If content is shorter than available height, scrollChild fills the entire scroll frame
    local finalHeight = math.max(yOffset, scrollFrameHeight)
    scrollChild:SetHeight(finalHeight)
    
    -- Reset scroll position
    scrollFrame:SetVerticalScroll(0)
    scrollFrame:UpdateScrollChildRect()
    
    C_Timer.After(0, function()
        if scrollFrame and scrollFrame:IsShown() then
            scrollFrame:SetVerticalScroll(0)
        end
    end)
    
    -- OK Button (bottom center) - Using Factory pattern
    local okBtn = ns.UI.Factory:CreateButton(dialog, 120, 32)
    okBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 15)
    
    -- Apply custom theme to OK button
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(okBtn,
            {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9},  -- Accent background
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
                {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1},
                {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1}
            )
        end
        okBtnText:SetTextColor(1, 1, 0.8)
    end)
    okBtn:SetScript("OnLeave", function(self)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self,
                {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9},
                {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}
            )
        end
        okBtnText:SetTextColor(1, 1, 1)
    end)
    
    dialog:Show()
end

