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
    dialog:SetSize(500, 600)
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
    
    -- Header frame (instead of texture)
    local header = CreateFrame("Frame", nil, dialog)
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
    
    -- Custom themed close button (top right)
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    closeBtn:SetNormalTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight", "ADD")
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)
    
    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -30, 50)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(450, 1) -- Height will be calculated
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Content
    local yOffset = 0
    local function AddText(text, fontType, color, spacing, centered)
        -- Map font types: "header", "title", "subtitle", "body", "small"
        local fs = FontManager:CreateFontString(scrollChild, fontType or "body", "OVERLAY")
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        fs:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -yOffset)
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
        line:SetPoint("LEFT", scrollChild, "LEFT", 0, -yOffset)
        line:SetPoint("RIGHT", scrollChild, "RIGHT", 0, -yOffset)
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        yOffset = yOffset + 15
    end
    
    AddText("Welcome to Warband Nexus!", "header", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8, true)
    AddText("Your comprehensive addon for managing Warband features, banks, currencies, reputations, and more.", "body", {0.8, 0.8, 0.8}, 15)
    
    AddDivider()
    
    -- Characters Tab
    AddText("Characters Tab", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Displays all characters you have logged into with a summary of their gold, levels, class colors, professions, and last played dates. Gold is automatically summed across all characters.", "body", {0.9, 0.9, 0.9}, 15)
    
    -- Items Tab
    AddText("Items Tab", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Updates automatically whenever you open your bank (including Warband Bank). Enable 'Enable Bank UI' to use the addon's bank manager, or disable it to keep using other bag/inventory addons. Use the search bar to find items across all Warband and character banks.", "body", {0.9, 0.9, 0.9}, 15)
    
    -- Storage Tab
    AddText("Storage Tab", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Aggregates all items from characters, Warband Bank, and Guild Bank. Search your entire inventory in one convenient location.", "body", {0.9, 0.9, 0.9}, 15)
    
    -- PvE Tab
    AddText("PvE Tab", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Track Great Vault progress, rewards, Mythic+ keystones, and raid lockouts across all your characters.", "body", {0.9, 0.9, 0.9}, 15)
    
    -- Reputations Tab
    AddText("Reputations Tab", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Two viewing modes:\n• Filtered: Smart filtering organized by 'Account-Wide' and 'Character-Specific' categories, displaying the highest progress across your account.\n• All Characters: Displays the standard Blizzard UI view for each character individually.\n\nNote: While active, you cannot collapse reputation headers in the default character panel.", "body", {0.9, 0.9, 0.9}, 15)
    
    -- Currency Tab
    AddText("Currency Tab", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Two filtering modes:\n• Filtered: Organizes and categorizes all currencies by expansion.\n• Non-Filtered: Matches the default Blizzard UI layout.\n• Hide Quantity 0: Automatically hides currencies with zero quantity.", "body", {0.9, 0.9, 0.9}, 15)
    
    -- Statistics Tab
    AddText("Statistics Tab", "title", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Displays achievement points, mount collections, battle pets, toys, and bag/bank slot usage for all characters.", "body", {0.9, 0.9, 0.9}, 15)
    
    AddDivider()
    
    -- Footer
    AddText("Thank you for your support!", "title", {0.2, 0.8, 0.2}, 8)
    AddText("If you encounter any bugs or have suggestions, please leave a comment on CurseForge. Your feedback helps make Warband Nexus better!", "body", {0.8, 0.8, 0.8}, 5)
    
    -- Update scroll child height
    scrollChild:SetHeight(yOffset)
    
    -- OK Button (bottom center)
    local okBtn = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
    okBtn:SetSize(100, 30)
    okBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 15)
    okBtn:SetText("OK")
    
    -- Use FontManager for button font
    local fontPath = FontManager:GetFontFace()
    local fontSize = FontManager:GetFontSize("body")
    local aa = FontManager:GetAAFlags()
    if fontPath and fontSize then
        okBtn:SetNormalFontObject(nil)  -- Clear template font object
        okBtn:SetFont(fontPath, fontSize, aa)
    end
    
    okBtn:SetScript("OnClick", function() dialog:Hide() end)
    
    dialog:Show()
end

