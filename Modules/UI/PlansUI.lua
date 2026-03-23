--[[
    Warband Nexus - Plans Tab UI
    User-driven goal tracker for mounts, pets, and toys
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Unique AceEvent handler identity for PlansUI
local PlansUIEvents = {}

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Import shared UI components
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local CreateSearchBox = ns.UI_CreateSearchBox
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateResultsContainer = ns.UI_CreateResultsContainer
local CreateIcon = ns.UI_CreateIcon
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor
local CreateExternalWindow = ns.UI_CreateExternalWindow
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local CreateTableRow = ns.UI_CreateTableRow
local CreateExpandableRow = ns.UI_CreateExpandableRow
local CardLayoutManager = ns.UI_CardLayoutManager

-- Loading state for collection scanning (per-category)
ns.PlansLoadingState = ns.PlansLoadingState or {
    -- Structure: { mount = { isLoading, loader }, pet = { isLoading, loader }, toy = { isLoading, loader } }
}
local PlanCardFactory = ns.UI_PlanCardFactory
local FormatNumber = ns.UI_FormatNumber
local FormatTextNumbers = ns.UI_FormatTextNumbers

-- Custom themed Try Count popup (addon-styled, replaces StaticPopup)
local tryCountPopup = nil
local function ShowTryCountPopup(planData, collectibleID)
    local COLORS = ns.UI_COLORS or {accent = {0.40, 0.20, 0.58}, accentDark = {0.28, 0.14, 0.41}, bg = {0.06, 0.06, 0.08}, border = {0.20, 0.20, 0.25}}
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager = ns.FontManager
    
    -- Reuse or create frame
    if not tryCountPopup then
        local f = CreateFrame("Frame", "WNTryCountPopup", UIParent, "BackdropTemplate")
        f:SetSize(300, 160)
        f:SetPoint("CENTER")
        f:EnableMouse(true)
        f:SetMovable(true)

        -- WindowManager: standardized strata/level + ESC + combat hide
        if ns.WindowManager then
            ns.WindowManager:ApplyStrata(f, ns.WindowManager.PRIORITY.POPUP)
            ns.WindowManager:Register(f, ns.WindowManager.PRIORITY.POPUP)
            ns.WindowManager:InstallESCHandler(f)
            ns.WindowManager:InstallDragHandler(f, f)
        else
            f:SetFrameStrata("FULLSCREEN_DIALOG")
            f:SetFrameLevel(200)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", f.StopMovingOrSizing)
        end
        
        -- Background
        if ApplyVisuals then
            ApplyVisuals(f, {0.04, 0.04, 0.06, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9})
        end
        
        -- Header bar
        local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
        header:SetHeight(32)
        header:SetPoint("TOPLEFT", 2, -2)
        header:SetPoint("TOPRIGHT", -2, -2)
        if ApplyVisuals then
            ApplyVisuals(header, {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
        
        -- Header title
        local headerTitle = FontManager:CreateFontString(header, "title", "OVERLAY")
        headerTitle:SetPoint("CENTER")
        headerTitle:SetText((ns.L and ns.L["SET_TRY_COUNT"]) or "Set Try Count")
        headerTitle:SetTextColor(1, 1, 1)
        f.headerTitle = headerTitle
        
        -- Plan name label
        local nameLabel = FontManager:CreateFontString(f, "body", "OVERLAY")
        nameLabel:SetPoint("TOP", header, "BOTTOM", 0, -12)
        nameLabel:SetJustifyH("CENTER")
        nameLabel:SetTextColor(0.9, 0.9, 0.9)
        f.nameLabel = nameLabel
        
        -- Edit box container
        local editBoxBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
        editBoxBg:SetSize(120, 28)
        editBoxBg:SetPoint("TOP", nameLabel, "BOTTOM", 0, -10)
        if ApplyVisuals then
            ApplyVisuals(editBoxBg, {0.02, 0.02, 0.03, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5})
        end
        
        -- Edit box
        local editBox = CreateFrame("EditBox", nil, editBoxBg)
        editBox:SetPoint("TOPLEFT", 8, -4)
        editBox:SetPoint("BOTTOMRIGHT", -8, 4)
        editBox:SetAutoFocus(false)
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(6)
        local fontFace = FontManager:GetFontFace()
        local fontSize = FontManager:GetFontSize("body")
        editBox:SetFont(fontFace, fontSize, "")
        editBox:SetTextColor(1, 1, 1)
        editBox:SetJustifyH("CENTER")
        f.editBox = editBox
        
        -- Buttons row
        local btnWidth, btnHeight = 90, 26
        
        -- Save button
        local saveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(btnWidth, btnHeight)
        saveBtn:SetPoint("TOPRIGHT", editBoxBg, "BOTTOM", -4, -10)
        if ApplyVisuals then
            ApplyVisuals(saveBtn, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
        end
        local saveBtnText = FontManager:CreateFontString(saveBtn, "body", "OVERLAY")
        saveBtnText:SetPoint("CENTER")
        saveBtnText:SetText((ns.L and ns.L["SAVE"]) or "Save")
        saveBtnText:SetTextColor(1, 1, 1)
        saveBtn:SetScript("OnEnter", function(self)
            if ApplyVisuals then ApplyVisuals(self, {0.12, 0.12, 0.14, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1}) end
        end)
        saveBtn:SetScript("OnLeave", function(self)
            if ApplyVisuals then ApplyVisuals(self, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}) end
        end)
        f.saveBtn = saveBtn
        
        -- Cancel button
        local cancelBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        cancelBtn:SetSize(btnWidth, btnHeight)
        cancelBtn:SetPoint("TOPLEFT", editBoxBg, "BOTTOM", 4, -10)
        if ApplyVisuals then
            ApplyVisuals(cancelBtn, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
        end
        local cancelBtnText = FontManager:CreateFontString(cancelBtn, "body", "OVERLAY")
        cancelBtnText:SetPoint("CENTER")
        cancelBtnText:SetText(CANCEL or "Cancel")
        cancelBtnText:SetTextColor(0.8, 0.8, 0.8)
        cancelBtn:SetScript("OnEnter", function(self)
            if ApplyVisuals then ApplyVisuals(self, {0.12, 0.12, 0.14, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8}) end
        end)
        cancelBtn:SetScript("OnLeave", function(self)
            if ApplyVisuals then ApplyVisuals(self, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6}) end
        end)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)
        
        -- Enter key saves
        editBox:SetScript("OnEnterPressed", function()
            f.saveBtn:Click()
        end)
        
        -- Escape key cancels
        editBox:SetScript("OnEscapePressed", function()
            f:Hide()
        end)
        
        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
                self:Hide()
            else
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end
        end)
        
        tryCountPopup = f
    end
    
    -- Populate data
    local popup = tryCountPopup
    local planName = planData.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    popup.nameLabel:SetText(planName)
    
    local currentCount = WarbandNexus and WarbandNexus.GetTryCount and WarbandNexus:GetTryCount(planData.type, collectibleID) or 0
    popup.editBox:SetText(tostring(currentCount))
    
    -- Wire save action
    popup.saveBtn:SetScript("OnClick", function()
        local count = tonumber(popup.editBox:GetText())
        if count and count >= 0 and WarbandNexus and WarbandNexus.SetTryCount then
            WarbandNexus:SetTryCount(planData.type, collectibleID, count)
            if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
        end
        popup:Hide()
    end)
    
    popup:Show()
    popup.editBox:SetFocus()
    popup.editBox:HighlightText()
end

-- Import shared UI layout constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local ROW_HEIGHT = GetLayout().rowHeight or 26
local ROW_SPACING = GetLayout().rowSpacing or 28
local HEADER_SPACING = GetLayout().HEADER_SPACING or GetLayout().headerSpacing or 40
local SECTION_SPACING = GetLayout().SECTION_SPACING or GetLayout().betweenSections or 8
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or GetLayout().sideMargin or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or GetLayout().topMargin or 8

-- Import PLAN_TYPES from PlansManager
local PLAN_TYPES = ns.PLAN_TYPES

-- Category definitions – My Plans always first, rest alphabetical
local CATEGORIES = {
    { key = "active", name = (ns.L and ns.L["CATEGORY_MY_PLANS"]) or "My Plans", icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { key = "achievement", name = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements", icon = "Interface\\Icons\\Achievement_General" },
    { key = "daily_tasks", name = (ns.L and ns.L["CATEGORY_DAILY_TASKS"]) or "Weekly Progress", icon = "Interface\\Icons\\INV_Misc_Note_06" },
    { key = "illusion", name = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions", iconAtlas = "UpgradeItem-32x32" },
    { key = "mount", name = (ns.L and ns.L["CATEGORY_MOUNTS"]) or "Mounts", iconAtlas = "dragon-rostrum" },
    { key = "pet", name = (ns.L and ns.L["CATEGORY_PETS"]) or "Pets", iconAtlas = "WildBattlePetCapturable" },
    { key = "title", name = (ns.L and ns.L["CATEGORY_TITLES"]) or "Titles", iconAtlas = "poi-legendsoftheharanir" },
    { key = "toy", name = (ns.L and ns.L["CATEGORY_TOYS"]) or "Toys", iconAtlas = "CreationCatalyst-32x32" },
    { key = "transmog", name = (ns.L and ns.L["CATEGORY_TRANSMOG"]) or "Transmog", iconAtlas = "poi-transmogrifier" },
}

-- Module state
local currentCategory = "active"
local currentDailyContentFilter = "midnight"
local searchText = ""
local showCompleted = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.plansShowCompleted or false
local showPlanned = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.plansShowPlanned or false

-- Throttle state for scan progress UI refreshes
local lastUIRefresh = 0

-- Icons (no unicode - use game textures)
local ICON_CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local ICON_CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local ICON_GOLD = "Interface\\MONEYFRAME\\UI-GoldIcon"

-- ============================================================================
-- SOURCE TEXT PARSER
-- ============================================================================

--[[
    Parse source text into structured parts
    @param source string - Raw source text from API
    @return table - Parsed parts { sourceType, zone, npc, cost, renown, scenario, raw }
]]
function WarbandNexus:ParseSourceText(source)
    local parts = {
        sourceType = nil,
        zone = nil,
        npc = nil,
        cost = nil,
        renown = nil,
        scenario = nil,
        raw = source,
        isVendor = false,
        isDrop = false,
        isPetBattle = false,
        isQuest = false,
    }
    
    if not source then return parts end
    
    -- Clean escape sequences from source text before parsing
    local cleanSource = source
    if self.CleanSourceText then
        cleanSource = self:CleanSourceText(source)
    else
        -- Fallback inline cleanup if CleanSourceText not available
        cleanSource = source:gsub("|T.-|t", "")  -- Remove texture tags
        cleanSource = cleanSource:gsub("|c%x%x%x%x%x%x%x%x", "")  -- Remove color codes
        cleanSource = cleanSource:gsub("|r", "")  -- Remove color reset
        cleanSource = cleanSource:gsub("|H.-|h", "")  -- Remove hyperlinks
        cleanSource = cleanSource:gsub("|h", "")  -- Remove closing hyperlink tags
    end
    
    -- Determine source type using Blizzard's localized BATTLE_PET_SOURCE_* globals
    -- These globals are auto-localized by WoW client (Drop, Quest, Vendor, etc.)
    local L = ns.L
    -- Single parse system for mount/pet/toy/plans. Order: more specific first.
    local sourcePatterns = {
        { pattern = BATTLE_PET_SOURCE_3 or "Vendor",                         type = "Vendor",      flagKey = "isVendor" },
        { pattern = (L and L["PARSE_SOLD_BY"]) or "Sold by",                 type = "Vendor",      flagKey = "isVendor" },
        { pattern = BATTLE_PET_SOURCE_1 or "Drop",                           type = "Drop",        flagKey = "isDrop" },
        { pattern = BATTLE_PET_SOURCE_5 or "Pet Battle",                     type = "Pet Battle",  flagKey = "isPetBattle" },
        { pattern = (L and L["SOURCE_TYPE_PUZZLE"]) or "Puzzle",             type = "Puzzle" },
        { pattern = BATTLE_PET_SOURCE_2 or "Quest",                          type = "Quest",       flagKey = "isQuest" },
        { pattern = BATTLE_PET_SOURCE_6 or "Achievement",                    type = "Achievement" },
        { pattern = (L and L["PARSE_FROM_ACHIEVEMENT"]) or "From Achievement", type = "Achievement" },
        { pattern = BATTLE_PET_SOURCE_4 or "Profession",                     type = "Crafted" },
        { pattern = (L and L["PARSE_CRAFTED"]) or "Crafted",                 type = "Crafted" },
        { pattern = BATTLE_PET_SOURCE_8 or "Promotion",                      type = "Promotion" },
        { pattern = BATTLE_PET_SOURCE_10 or "In-Game Shop",                  type = "Promotion" },
        { pattern = BATTLE_PET_SOURCE_9 or "Trading Card",                   type = "Promotion" },
        { pattern = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post", type = "Trading Post" },
        { pattern = BATTLE_PET_SOURCE_7 or "World Event",                     type = "World Event" },
        { pattern = (L and L["SOURCE_TYPE_TREASURE"]) or "Treasure",          type = "Treasure" },
        { pattern = (L and L["PARSE_DISCOVERY"]) or "Discovery",             type = "Treasure" },
        { pattern = (L and L["SOURCE_TYPE_RENOWN"]) or "Renown",             type = "Reputation" },
        { pattern = (L and L["PARSE_PARAGON"]) or "Paragon",                type = "Reputation" },
        { pattern = (L and L["PARSE_COVENANT"]) or "Covenant",               type = "Reputation" },
        { pattern = REPUTATION or "Reputation",                              type = "Reputation" },
        { pattern = (L and L["SOURCE_TYPE_PVP"]) or PVP or "PvP",            type = "PvP" },
        { pattern = (L and L["PARSE_GARRISON"]) or "Garrison",               type = "Quest" },
        { pattern = (L and L["PARSE_MISSION"]) or "Mission",                type = "Quest" },
        { pattern = (L and L["PARSE_LOCATION"]) or (L and L["LOCATION_LABEL"] and L["LOCATION_LABEL"]:gsub(":%s*$", "")) or "Location", type = "Drop" },
        { pattern = ZONE or "Zone",                                          type = "Drop" },
    }
    
    for _, entry in ipairs(sourcePatterns) do
        if entry.pattern and cleanSource:find(entry.pattern, 1, true) then
            parts.sourceType = entry.type
            if entry.flagKey then
                parts[entry.flagKey] = true
            end
            break
        end
    end
    
    -- Extract vendor/NPC name (use cleaned source)
    local vendor = cleanSource:match("Vendor:%s*([^\n]+)") or cleanSource:match("Sold by:%s*([^\n]+)")
    if vendor then
        parts.npc = vendor:gsub("%s*$", "")  -- Trim trailing whitespace
    end
    
    -- Extract zone (use cleaned source)
    local zone = cleanSource:match("Zone:%s*([^\n]+)")
    if zone then
        parts.zone = zone:gsub("%s*$", "")
    end
    
    -- Extract cost (gold) - use cleaned source
    local goldCost = cleanSource:match("Cost:%s*([%d,]+)%s*[gG]old") or cleanSource:match("([%d,]+)%s*[gG]old")
    if goldCost then
        parts.cost = goldCost .. " " .. ((ns.L and ns.L["GOLD_LABEL"]) or "Gold")
    end
    
    -- Extract cost (other currencies) - use cleaned source
    local currencyCost = cleanSource:match("Cost:%s*([%d,]+)%s*([^\n]+)")
    if currencyCost and not goldCost then
        parts.cost = currencyCost
    end
    
    -- Extract renown requirement - use cleaned source
    local renown = cleanSource:match("Renown%s*(%d+)") or cleanSource:match("Renown:%s*(%d+)")
    if renown then
        parts.renown = ((ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown") .. " " .. renown
    end
    
    -- Extract scenario - use cleaned source
    local scenario = cleanSource:match("Scenario:%s*([^\n]+)")
    if scenario then
        parts.scenario = scenario:gsub("%s*$", "")
    end
    
    -- Pet Battle location - use cleaned source
    local petBattleZone = cleanSource:match("Pet Battle:%s*([^\n]+)")
    if petBattleZone then
        parts.zone = petBattleZone:gsub("%s*$", "")
    end
    
    -- Drop source - use cleaned source
    local dropSource = cleanSource:match("Drop:%s*([^\n]+)")
    if dropSource then
        parts.npc = dropSource:gsub("%s*$", "")
    end
    
    return parts
end

-- ============================================================================
-- MAIN DRAW FUNCTION
-- ============================================================================

function WarbandNexus:DrawPlansTab(parent)
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    -- Hide standardized empty state card
    HideEmptyStateCard(parent, "plans")
    
    local width = parent:GetWidth() - 20

    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = 8

    -- Check if module is enabled (early check for buttons)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.plans ~= false
    
    -- Initialize expanded cards state (persist across refreshes)
    if not ns.expandedCards then
        ns.expandedCards = {}
    end
    
    -- ===== TITLE CARD (in fixedHeader - non-scrolling) =====
    local titleCard = CreateCard(headerParent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
    -- Header icon with ring border (standardized)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("plans"))
    
    -- Use factory pattern for standardized header layout
    local CreateCardHeaderLayout = ns.UI_CreateCardHeaderLayout
    
    -- Count active (non-completed) plans only, excluding daily_quests
    local allPlans = self:GetActivePlans() or {}
    local activePlanCount = 0
    for _, plan in ipairs(allPlans) do
        if plan.type ~= "daily_quests" then
            local progress = self:GetResolvedPlanProgress(plan)
            local isComplete = (progress and progress.collected) or (plan.completed == true)
            if not isComplete then
                activePlanCount = activePlanCount + 1
            end
        end
    end
    
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local collectionPlansLabel = (ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List"
    local titleTextContent = "|cff" .. hexColor .. collectionPlansLabel .. "|r"
    local plansSubtitle = (ns.L and ns.L["PLANS_SUBTITLE_TEXT"]) or "Track your weekly goals & collections"
    local activePlanText = activePlanCount ~= 1
        and string.format((ns.L and ns.L["ACTIVE_PLANS_FORMAT"]) or "%d active plans", activePlanCount)
        or string.format((ns.L and ns.L["ACTIVE_PLAN_FORMAT"]) or "%d active plan", activePlanCount)
    local subtitleTextContent = plansSubtitle .. " • " .. activePlanText
    
    -- Create container for text group (using Factory pattern, NO BORDER)
    local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40, false)
    
    -- Create title text (header font, colored)
    local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
    titleText:SetText(titleTextContent)
    titleText:SetJustifyH("LEFT")
    
    -- Create subtitle text
    local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
    subtitleText:SetText(subtitleTextContent)
    subtitleText:SetTextColor(1, 1, 1)  -- White
    subtitleText:SetJustifyH("LEFT")
    
    -- Position texts: label at CENTER (0px), value at CENTER (-4px) - matching factory pattern
    titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)  -- Label at center
    titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)  -- Value below center
    subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    
    -- Position container: LEFT from icon, CENTER vertically to CARD (no checkbox)
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)  -- Center to card!
    
    -- Only show buttons and "Show Completed" checkbox if module is enabled
    if moduleEnabled then
        -- Add Custom button (using shared widget)
        local addCustomBtn = CreateThemedButton(titleCard, (ns.L and ns.L["ADD_CUSTOM"]) or "Add Custom", 100)
        addCustomBtn:SetPoint("RIGHT", -15, 0)
        -- Store reference for state management
        self.addCustomBtn = addCustomBtn
        addCustomBtn:SetScript("OnClick", function()
            self:ShowCustomPlanDialog()
        end)
        
        -- Add Vault button (using shared widget)
        local addWeeklyBtn = CreateThemedButton(titleCard, (ns.L and ns.L["ADD_VAULT"]) or "Add Vault", 100)
        addWeeklyBtn:SetPoint("RIGHT", addCustomBtn, "LEFT", -8, 0)
        addWeeklyBtn:SetScript("OnClick", function()
            self:ShowWeeklyPlanDialog()
        end)
        
        -- Add Quest button (opens Daily Plan dialog)
        local addDailyBtn = CreateThemedButton(titleCard, (ns.L and ns.L["ADD_QUEST"]) or "Add Quest", 100)
        addDailyBtn:SetPoint("RIGHT", addWeeklyBtn, "LEFT", -8, 0)
        addDailyBtn:SetScript("OnClick", function()
            self:ShowDailyPlanDialog()
        end)

        -- Checkbox (using shared widget) - Next to Add Quest button
        local checkbox = CreateThemedCheckbox(titleCard, showCompleted)
        if not checkbox then
            DebugPrint("|cffff0000WN DEBUG: CreateThemedCheckbox returned nil! titleCard:|r", titleCard)
            return
        end
        
        if not checkbox.HasScript then
            DebugPrint("|cffff0000WN DEBUG: Checkbox missing HasScript method! Type:|r", checkbox:GetObjectType())
        elseif not checkbox:HasScript("OnClick") then
            DebugPrint("|cffffff00WN DEBUG: Checkbox type", checkbox:GetObjectType(), "doesn't support OnClick|r")
        end
        
        -- Reset Completed Plans button (left of Add Quest button)
        local resetBtn = CreateThemedButton(titleCard, (ns.L and ns.L["RESET_LABEL"]) or "Reset", 80)
        resetBtn:SetPoint("RIGHT", addDailyBtn, "LEFT", -10, 0)
        
        -- Checkbox (left of Reset button)
        checkbox:SetPoint("RIGHT", resetBtn, "LEFT", -10, 0)
        resetBtn:SetScript("OnClick", function()
            -- Confirmation via StaticPopup
            StaticPopupDialogs["WN_RESET_COMPLETED_PLANS"] = {
                text = (ns.L and ns.L["RESET_COMPLETED_CONFIRM"]) or "Are you sure you want to remove ALL completed plans?\n\nThis cannot be undone!",
                button1 = (ns.L and ns.L["YES_RESET"]) or "Yes, Reset",
                button2 = CANCEL or "Cancel",
                OnAccept = function()
                    if WarbandNexus.ResetCompletedPlans then
                        local count = WarbandNexus:ResetCompletedPlans()
                        WarbandNexus:Print(string.format((ns.L and ns.L["REMOVED_PLANS_FORMAT"]) or "Removed %d completed plan(s).", count))
                        if WarbandNexus.RefreshUI then
                            WarbandNexus:RefreshUI()
                        end
                    end
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("WN_RESET_COMPLETED_PLANS")
        end)
        
        -- Tooltip for reset button
        resetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText((ns.L and ns.L["REMOVE_COMPLETED_TOOLTIP"]) or "Remove all completed plans from your My Plans list. This will delete all completed custom plans and remove completed mounts/pets/toys from your plans. This action cannot be undone!", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        -- Add text label for "Show Completed" checkbox (left of checkbox)
        local checkboxLabel = FontManager:CreateFontString(titleCard, "body", "OVERLAY")
        checkboxLabel:SetPoint("RIGHT", checkbox, "LEFT", -8, 0)
        checkboxLabel:SetText((ns.L and ns.L["SHOW_COMPLETED"]) or "Show Completed")
        checkboxLabel:SetTextColor(0.9, 0.9, 0.9)
        
        -- Override OnClick to add filtering (with safety check)
        local originalOnClick = nil
        if checkbox and checkbox.GetScript then
            local success, result = pcall(function() return checkbox:GetScript("OnClick") end)
            if success then
                originalOnClick = result
            else
                DebugPrint("WarbandNexus DEBUG: GetScript('OnClick') failed for checkbox:", result)
            end
        end
        checkbox:SetScript("OnClick", function(self)
            if originalOnClick then originalOnClick(self) end
            showCompleted = self:GetChecked()
            -- Save to DB
            if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.plansShowCompleted = showCompleted
            end
            -- Refresh UI to apply filter
            if WarbandNexus.RefreshUI then
                WarbandNexus:RefreshUI()
            end
        end)
        
        -- Add tooltip (keep border hover effect from shared widget)
        local originalOnEnter = nil
        if checkbox and checkbox.GetScript then
            local success, result = pcall(function() return checkbox:GetScript("OnEnter") end)
            if success then
                originalOnEnter = result
            end
        end
        checkbox:SetScript("OnEnter", function(self)
            if originalOnEnter then originalOnEnter(self) end
        end)
        
        local originalOnLeave = nil
        if checkbox and checkbox.GetScript then
            local success, result = pcall(function() return checkbox:GetScript("OnLeave") end)
            if success then
                originalOnLeave = result
            end
        end
        checkbox:SetScript("OnLeave", function(self)
            if originalOnLeave then originalOnLeave(self) end
        end)
        
        -- === "Show Planned" checkbox (left of "Show Completed" label) ===
        local plannedCheckbox = CreateThemedCheckbox(titleCard, showPlanned)
        if plannedCheckbox then
            plannedCheckbox:SetPoint("RIGHT", checkboxLabel, "LEFT", -16, 0)
            
            local plannedLabel = FontManager:CreateFontString(titleCard, "body", "OVERLAY")
            plannedLabel:SetPoint("RIGHT", plannedCheckbox, "LEFT", -8, 0)
            plannedLabel:SetText((ns.L and ns.L["SHOW_PLANNED"]) or "Show Planned")
            plannedLabel:SetTextColor(0.9, 0.9, 0.9)
            
            local origPlannedOnClick = nil
            if plannedCheckbox.GetScript then
                local ok2, res2 = pcall(function() return plannedCheckbox:GetScript("OnClick") end)
                if ok2 then origPlannedOnClick = res2 end
            end
            plannedCheckbox:SetScript("OnClick", function(self)
                if origPlannedOnClick then origPlannedOnClick(self) end
                showPlanned = self:GetChecked()
                if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile then
                    WarbandNexus.db.profile.plansShowPlanned = showPlanned
                end
                if WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end)
            
            -- Preserve hover effects from shared widget
            local origPlannedEnter = nil
            if plannedCheckbox.GetScript then
                local ok3, res3 = pcall(function() return plannedCheckbox:GetScript("OnEnter") end)
                if ok3 then origPlannedEnter = res3 end
            end
            plannedCheckbox:SetScript("OnEnter", function(self)
                if origPlannedEnter then origPlannedEnter(self) end
            end)
            
            local origPlannedLeave = nil
            if plannedCheckbox.GetScript then
                local ok4, res4 = pcall(function() return plannedCheckbox:GetScript("OnLeave") end)
                if ok4 then origPlannedLeave = res4 end
            end
            plannedCheckbox:SetScript("OnLeave", function(self)
                if origPlannedLeave then origPlannedLeave(self) end
            end)
        end
    end
    
    -- Check if module is disabled (before showing controls)
    if not moduleEnabled then
        titleCard:Show()
        headerYOffset = headerYOffset + GetLayout().afterHeader
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, 8, (ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List")
        return 8 + cardHeight
    end

    titleCard:Show()
    headerYOffset = headerYOffset + GetLayout().afterHeader
    
    -- One-time event registration (following CurrencyUI pattern)
    if not self._plansEventRegistered then
        local Constants = ns.Constants
        
        -- Plan CRUD events (API > DB > UI)
        -- NOTE: Uses PlansUIEvents as 'self' key to avoid overwriting PlansTrackerWindow's handler.
        -- String method references must be wrapped in closures since PlansUIEvents has no methods.
        WarbandNexus.RegisterMessage(PlansUIEvents, "WN_PLANS_UPDATED", function(event, data)
            if WarbandNexus.OnPlansUpdated then
                WarbandNexus:OnPlansUpdated(event, data)
            end
        end)
        
        -- Collection scan progress (throttled UI refresh for loading indicators)
        if Constants and Constants.EVENTS then
            WarbandNexus.RegisterMessage(PlansUIEvents, Constants.EVENTS.COLLECTION_SCAN_PROGRESS, function(_, data)
                local now = debugprofilestop()
                if (now - lastUIRefresh) < 500 then return end
                
                if not self:IsStillOnTab("plans") then return end
                local scanCategory = data and data.category
                if scanCategory ~= currentCategory and currentCategory ~= "active" then return end
                
                lastUIRefresh = now
                C_Timer.After(0.05, function()
                    if self:IsStillOnTab("plans") then
                        self:RefreshUI()
                    end
                end)
            end)
            
            -- Collection scan complete (final refresh)
            WarbandNexus.RegisterMessage(PlansUIEvents, Constants.EVENTS.COLLECTION_SCAN_COMPLETE, function(_, data)
                if not self:IsStillOnTab("plans") then return end
                local scanCategory = data and data.category
                if scanCategory ~= currentCategory and currentCategory ~= "active" then return end
                
                C_Timer.After(0.1, function()
                    if self:IsStillOnTab("plans") then
                        self:RefreshUI()
                    end
                end)
            end)
            -- Uncollected cache updated (e.g. mount/pet/toy obtained) — refresh so completed items disappear from lists
            WarbandNexus.RegisterMessage(PlansUIEvents, Constants.EVENTS.COLLECTION_UPDATED, function(_, updatedType)
                if not self:IsStillOnTab("plans") then return end
                if updatedType == "mount" or updatedType == "pet" or updatedType == "toy" then
                    C_Timer.After(0.05, function()
                        if self:IsStillOnTab("plans") and self.RefreshUI then self:RefreshUI() end
                    end)
                end
            end)
        end
        
        self._plansEventRegistered = true
    end
    
    -- ===== CATEGORY BUTTONS (in fixedHeader - non-scrolling) =====
    local categoryBar = ns.UI.Factory:CreateContainer(headerParent, nil, nil, false)
    categoryBar:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    categoryBar:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
    local DEFAULT_CAT_BTN_WIDTH = 150
    local catBtnHeight = 40
    local catBtnSpacing = 8
    local catIconSize = 28
    local catIconLeftPad = 10
    local catIconTextGap = 8
    local catTextRightPad = 10
    local maxWidth = parent:GetWidth() - 20  -- Available width
    
    -- Pre-calculate button widths based on text (icon + padding + text + padding)
    local catBtnWidths = {}
    for i, cat in ipairs(CATEGORIES) do
        -- Measure text width using a temporary FontString
        local tempFs = FontManager:CreateFontString(categoryBar, "body", "OVERLAY")
        tempFs:SetText(cat.name)
        local textW = tempFs:GetStringWidth() or 0
        tempFs:Hide()
        local needed = catIconLeftPad + catIconSize + catIconTextGap + textW + catTextRightPad
        catBtnWidths[i] = math.max(needed, DEFAULT_CAT_BTN_WIDTH)
    end
    
    local currentX = 0
    local currentRow = 0
    
    for i, cat in ipairs(CATEGORIES) do
        local catBtnWidth = catBtnWidths[i]
        
        -- Check if button fits in current row
        if currentX + catBtnWidth > maxWidth and currentX > 0 then
            -- Move to next row
            currentX = 0
            currentRow = currentRow + 1
        end
        
        local btn = ns.UI.Factory:CreateButton(categoryBar, catBtnWidth, catBtnHeight)
        btn:SetPoint("TOPLEFT", currentX, -(currentRow * (catBtnHeight + catBtnSpacing)))
        
        -- Check if this is the active category
        local isActive = (cat.key == currentCategory)
        local acc = COLORS.accent

        if ApplyVisuals then
            if isActive then
                ApplyVisuals(btn, {acc[1] * 0.3, acc[2] * 0.3, acc[3] * 0.3, 1}, {acc[1], acc[2], acc[3], 1})
            else
                ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6, 1})
            end
        end

        -- Apply highlight effect (safe check for Factory)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end

        -- Active indicator bar (Collections/Items sub-tab ile aynı)
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetHeight(3)
        activeBar:SetPoint("BOTTOMLEFT", 8, 4)
        activeBar:SetPoint("BOTTOMRIGHT", -8, 4)
        activeBar:SetColorTexture(acc[1], acc[2], acc[3], 1)
        activeBar:SetAlpha(isActive and 1 or 0)
        btn.activeBar = activeBar

        -- Use atlas icon if available, otherwise use regular icon path
        local iconFrame
        if cat.iconAtlas then
            -- Create frame for atlas icon (using Factory pattern)
            iconFrame = ns.UI.Factory:CreateContainer(btn, 28, 28)
        iconFrame:SetPoint("LEFT", 10, 0)
            iconFrame:EnableMouse(false)
            
            local iconTexture = iconFrame:CreateTexture(nil, "OVERLAY")
            iconTexture:SetAllPoints()
            local iconSuccess = pcall(function()
                iconTexture:SetAtlas(cat.iconAtlas, false)
            end)
            if not iconSuccess then
                iconFrame:Hide()
                iconFrame = nil
            else
                iconTexture:SetSnapToPixelGrid(false)
                iconTexture:SetTexelSnappingBias(0)
                iconFrame:Show()  -- CRITICAL: Show atlas icon!
            end
        end
        
        -- Fallback to regular icon if atlas failed or not available
        if not iconFrame and cat.icon then
            iconFrame = CreateIcon(btn, cat.icon, 28, false, nil, true)
            iconFrame:SetPoint("LEFT", 10, 0)
            iconFrame:Show()  -- CRITICAL: Show category tab icon (My Plans, Daily Tasks, Achievements)!
        end
        
        local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
        label:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
        label:SetText(cat.name)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        btn._text = label
        if isActive then
            label:SetTextColor(1, 1, 1)
            local font, size = label:GetFont()
            if font and size then label:SetFont(font, size, "OUTLINE") end
        else
            label:SetTextColor(0.7, 0.7, 0.7)
            local font, size = label:GetFont()
            if font and size then label:SetFont(font, size, "") end
        end

        btn:SetScript("OnClick", function()
            if currentCategory == cat.key then return end
            currentCategory = cat.key
            searchText = ""
            
            -- Defer UI refresh to next frame to prevent button freeze
            C_Timer.After(0.05, function()
                if not self or not self.RefreshUI then return end
                self:RefreshUI()
            end)
        end)
        
        -- Update X position for next button
        currentX = currentX + catBtnWidth + catBtnSpacing
    end
    
    -- Set categoryBar height based on rows
    -- Formula: (rows * buttonHeight) + (gaps_between_rows * spacing)
    -- Example: 2 rows = 2 * 40px + 1 * 8px = 88px (not 96px!)
    local totalHeight = (currentRow + 1) * catBtnHeight + currentRow * catBtnSpacing
    categoryBar:SetHeight(totalHeight)
    
    headerYOffset = headerYOffset + totalHeight + GetLayout().afterElement

    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    local yOffset = 8

    -- ===== SEARCH BAR FOR MY PLANS (active tab only) =====
    if currentCategory == "active" then
        local searchBar = ns.UI.Factory:CreateContainer(parent, nil, 32, false)
        searchBar:SetPoint("TOPLEFT", 10, -yOffset)
        searchBar:SetPoint("TOPRIGHT", -10, -yOffset)
        if ApplyVisuals then
            ApplyVisuals(searchBar, { 0.06, 0.06, 0.08, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7 })
        end

        local searchIcon = searchBar:CreateTexture(nil, "OVERLAY")
        searchIcon:SetSize(14, 14)
        searchIcon:SetPoint("LEFT", 8, 0)
        searchIcon:SetAtlas("common-search-magnifyingglass")
        searchIcon:SetVertexColor(0.6, 0.6, 0.6)

        local searchInput = ns.UI.Factory:CreateEditBox(searchBar)
        searchInput:SetSize(1, 26)
        searchInput:SetPoint("LEFT", searchIcon, "RIGHT", 6, 0)
        searchInput:SetPoint("RIGHT", searchBar, "RIGHT", -8, 0)
        searchInput:SetFontObject(ChatFontNormal)
        searchInput:SetTextColor(1, 1, 1, 1)
        searchInput:SetAutoFocus(false)
        searchInput:SetMaxLetters(50)
        -- Placeholder text (search plans)
        local searchPlaceholder = (ns.L and ns.L["SEARCH_PLANS"]) or "Search plans..."
        searchInput.Instructions = searchInput:CreateFontString(nil, "ARTWORK")
        searchInput.Instructions:SetFontObject(ChatFontNormal)
        searchInput.Instructions:SetPoint("LEFT", 0, 0)
        searchInput.Instructions:SetPoint("RIGHT", 0, 0)
        searchInput.Instructions:SetJustifyH("LEFT")
        searchInput.Instructions:SetTextColor(0.5, 0.5, 0.5, 0.8)
        searchInput.Instructions:SetText(searchPlaceholder)
        if ns._plansActiveSearch and ns._plansActiveSearch ~= "" then
            searchInput:SetText(ns._plansActiveSearch)
            searchInput.Instructions:Hide()
        end
        searchInput:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
            ns._plansActiveSearch = nil
            if self.Instructions then self.Instructions:Show() end
            if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
        end)
        searchInput:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end  -- Ignore programmatic SetText calls
            local text = self:GetText() or ""
            ns._plansActiveSearch = (text ~= "") and text or nil
            -- Show/hide placeholder
            if self.Instructions then
                if text ~= "" then self.Instructions:Hide() else self.Instructions:Show() end
            end
            if WarbandNexus._plansSearchTimer then
                WarbandNexus._plansSearchTimer:Cancel()
            end
            WarbandNexus._plansSearchTimer = C_Timer.NewTimer(0.3, function()
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end)
        end)
        searchBar:EnableMouse(true)
        searchBar:SetScript("OnMouseDown", function() searchInput:SetFocus() end)
        searchBar:Show()

        yOffset = yOffset + 32 + GetLayout().afterElement
    end

    -- ===== CONTENT AREA =====
    if currentCategory == "active" or currentCategory == "daily_tasks" then
        yOffset = self:DrawActivePlans(parent, yOffset, width, currentCategory)
    else
        yOffset = self:DrawBrowser(parent, yOffset, width, currentCategory)
    end
    
    return yOffset + 20
end

-- ============================================================================
-- ACTIVE PLANS DISPLAY
-- ============================================================================

local function GetCategoryStats(plan, categoryKey)
    if not plan or not plan.questTypes or not plan.questTypes[categoryKey] then
        return 0, 0
    end
    local questList = (plan.quests and plan.quests[categoryKey]) or {}
    local total, completed = 0, 0
    for i = 1, #questList do
        local q = questList[i]
        if q and not q.isSubQuest then
            total = total + 1
            if q.isComplete then completed = completed + 1 end
        end
    end
    return completed, total
end

local function FormatTimeLeft(minutes)
    if not minutes or minutes <= 0 then return "" end
    local L = ns.L
    local Day = (L and L["PLAYED_DAY"]) or "Day"
    local Days = (L and L["PLAYED_DAYS"]) or "Days"
    local Hour = (L and L["PLAYED_HOUR"]) or "Hour"
    local Hours = (L and L["PLAYED_HOURS"]) or "Hours"
    local Minute = (L and L["PLAYED_MINUTE"]) or "Minute"
    local Minutes = (L and L["PLAYED_MINUTES"]) or "Minutes"
    if minutes >= 1440 then
        local days = math.floor(minutes / 1440)
        local hours = math.floor((minutes % 1440) / 60)
        if hours > 0 then
            return string.format("%d %s %d %s", days, days == 1 and Day or Days, hours, hours == 1 and Hour or Hours)
        end
        return string.format("%d %s", days, days == 1 and Day or Days)
    elseif minutes >= 60 then
        local hours = math.floor(minutes / 60)
        local mins = minutes % 60
        if mins > 0 then
            return string.format("%d %s %d %s", hours, hours == 1 and Hour or Hours, mins, mins == 1 and Minute or Minutes)
        end
        return string.format("%d %s", hours, hours == 1 and Hour or Hours)
    end
    return string.format("%d %s", minutes, minutes == 1 and Minute or Minutes)
end

local EVENT_GROUP_NAMES = {
    soiree     = "Saltheril's Soiree",
    abundance  = "Abundance",
    haranir    = "Legends of the Haranir",
    stormarion = "Stormarion Assault",
}

local function AttachQuestRowTooltip(frame, quest)
    frame:SetScript("OnEnter", function(self)
        local lines = {}
        if quest.description and quest.description ~= "" then
            lines[#lines + 1] = { text = quest.description, color = {0.9, 0.9, 0.9} }
        end
        if quest.isSubQuest and quest.eventGroup then
            local parentName = EVENT_GROUP_NAMES[quest.eventGroup] or quest.eventGroup
            lines[#lines + 1] = { text = format((ns.L and ns.L["PART_OF_FORMAT"]) or "Part of: %s", parentName), color = {0.8, 0.5, 1.0} }
        end
        if quest.zone and quest.zone ~= "" then
            lines[#lines + 1] = { text = quest.zone, color = {0.7, 0.7, 0.7} }
        end
        if quest.objective and quest.objective ~= "" then
            lines[#lines + 1] = { text = quest.objective, color = {1, 1, 1} }
        end
        if quest.progress and not quest.isComplete then
            local pct = math.floor((quest.progress.percent or 0) * 100)
            lines[#lines + 1] = {
                text = string.format("Progress: %d/%d (%d%%)", quest.progress.totalFulfilled or 0, quest.progress.totalRequired or 0, pct),
                color = pct >= 100 and {0.27, 1, 0.27} or {1, 0.82, 0.2},
            }
        end
        if quest.timeLeft and quest.timeLeft > 0 then
            local timeColor = quest.timeLeft < 60 and {1, 0.3, 0.3} or {0.7, 0.7, 0.7}
            lines[#lines + 1] = { text = FormatTimeLeft(quest.timeLeft) .. " remaining", color = timeColor }
        end
        if quest.isComplete then
            lines[#lines + 1] = { text = "|cff44ff44" .. ((ns.L and ns.L["COMPLETE_LABEL"]) or "Complete") .. "|r", color = {0.27, 1, 0.27} }
        elseif quest.isLocked then
            lines[#lines + 1] = { text = "|cffff9933" .. ((ns.L and ns.L["LOCKED_WORLD_QUESTS"]) or "Locked — complete World Quests to unlock") .. "|r", color = {1, 0.6, 0.2} }
        end
        if quest.questID then
            lines[#lines + 1] = { text = format((ns.L and ns.L["QUEST_ID_FORMAT"]) or "Quest ID: %s", quest.questID), color = {0.5, 0.5, 0.5} }
        end

        if ns.TooltipService and ns.TooltipService.Show then
            ns.TooltipService:Show(self, {
                type = "custom",
                title = quest.title or "Quest",
                icon = false,
                anchor = "ANCHOR_RIGHT",
                lines = lines,
            })
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(quest.title or "Quest", 1, 1, 1)
            for i = 1, #lines do
                local c = lines[i].color or {1, 1, 1}
                GameTooltip:AddLine(lines[i].text, c[1], c[2], c[3], true)
            end
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        if ns.TooltipService and ns.TooltipService.Hide then
            ns.TooltipService:Hide()
        else
            GameTooltip:Hide()
        end
    end)
end

function WarbandNexus:DrawDailyTasksView(parent, yOffset, width, plans)
    local filteredPlans = {}
    for i = 1, #plans do
        if plans[i].contentType == "midnight" then
            filteredPlans[#filteredPlans + 1] = plans[i]
        end
    end

    table.sort(filteredPlans, function(a, b)
        return ((a.characterName or "") .. (a.characterRealm or ""))
             < ((b.characterName or "") .. (b.characterRealm or ""))
    end)

    if #filteredPlans == 0 then
        local _, height = CreateEmptyStateCard(parent, "plans", yOffset)
        return yOffset + height + 10
    end

    local CATEGORIES = ns.QUEST_CATEGORIES or {}
    local CAT_DISPLAY = ns.CATEGORY_DISPLAY or {}
    local ROW_H = GetLayout().rowHeight
    local CAT_HEADER_H = GetLayout().headerHeight
    local expandedGroups = ns.UI_GetExpandedGroups and ns.UI_GetExpandedGroups() or {}

    -- ===== WEEKLY RESET TIMER BAR =====
    local resetBarH = 30
    local resetBar = CreateCard(parent, resetBarH)
    resetBar:SetPoint("TOPLEFT", 10, -yOffset)
    resetBar:SetPoint("TOPRIGHT", -10, -yOffset)
    if ApplyVisuals then
        ApplyVisuals(resetBar, {0.06, 0.04, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7})
    end

    local resetIcon = resetBar:CreateTexture(nil, "ARTWORK")
    resetIcon:SetSize(16, 16)
    resetIcon:SetPoint("LEFT", 12, 0)
    resetIcon:SetAtlas("characterupdate_clock-icon", true)

    local resetLabel = FontManager:CreateFontString(resetBar, "body", "OVERLAY")
    resetLabel:SetPoint("LEFT", resetIcon, "RIGHT", 6, 0)
    resetLabel:SetTextColor(0.8, 0.8, 0.8)
    resetLabel:SetText((ns.L and ns.L["WEEKLY_RESET_LABEL"]) or "Weekly Reset")

    local resetTimeText = FontManager:CreateFontString(resetBar, "body", "OVERLAY")
    resetTimeText:SetPoint("RIGHT", -12, 0)
    resetTimeText:SetTextColor(0.3, 0.9, 0.3)
    do
        local ok, seconds = pcall(function()
            if self.GetWeeklyResetTime then
                return self:GetWeeklyResetTime() - GetServerTime()
            elseif C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
                return C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
            end
            return 0
        end)
        local sec = (ok and type(seconds) == "number") and seconds or 0
        resetTimeText:SetText(ns.Utilities:FormatTimeCompact(sec))
    end

    resetBar.timeSinceUpdate = 0
    resetBar:SetScript("OnUpdate", function(self2, elapsed)
        self2.timeSinceUpdate = self2.timeSinceUpdate + elapsed
        if self2.timeSinceUpdate >= 60 then
            self2.timeSinceUpdate = 0
            local ok2, sec2 = pcall(function()
                if WarbandNexus.GetWeeklyResetTime then
                    return WarbandNexus:GetWeeklyResetTime() - GetServerTime()
                elseif C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
                    return C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
                end
                return 0
            end)
            local s = (ok2 and type(sec2) == "number") and sec2 or 0
            resetTimeText:SetText(ns.Utilities:FormatTimeCompact(s))
        end
    end)

    resetBar:Show()
    yOffset = yOffset + resetBarH + 6

    -- ===== CROSS-CHARACTER SUMMARY CARD =====
    local summaryGroupKey = "dq_summary"
    local summaryExpanded = (expandedGroups[summaryGroupKey] ~= false)

    local summaryHeaderH = 32
    local summaryHeader = CreateCard(parent, summaryHeaderH)
    summaryHeader:SetPoint("TOPLEFT", 10, -yOffset)
    summaryHeader:SetPoint("TOPRIGHT", -10, -yOffset)
    summaryHeader:EnableMouse(true)

    local summaryAccent = summaryHeader:CreateTexture(nil, "ARTWORK")
    summaryAccent:SetSize(3, summaryHeaderH - 6)
    summaryAccent:SetPoint("LEFT", 4, 0)
    summaryAccent:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)

    local summaryArrow = summaryHeader:CreateTexture(nil, "ARTWORK")
    summaryArrow:SetSize(16, 16)
    summaryArrow:SetPoint("LEFT", 10, 0)
    if summaryExpanded then
        summaryArrow:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", false)
    else
        summaryArrow:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", false)
    end
    summaryArrow:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])

    local summaryTitle = FontManager:CreateFontString(summaryHeader, "body", "OVERLAY")
    summaryTitle:SetPoint("LEFT", 30, 0)
    summaryTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    summaryTitle:SetText((ns.L and ns.L["CROSS_CHAR_SUMMARY"]) or "Character Overview")

    summaryHeader:SetScript("OnMouseDown", function()
        if ns.UI_SetExpandedGroup then
            ns.UI_SetExpandedGroup(summaryGroupKey, not summaryExpanded)
        elseif expandedGroups then
            expandedGroups[summaryGroupKey] = not summaryExpanded
        end
        if self.RefreshUI then self:RefreshUI() end
    end)
    summaryHeader:SetScript("OnEnter", function(f)
        if ApplyVisuals then
            ApplyVisuals(f, {0.10, 0.10, 0.12, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
        end
    end)
    summaryHeader:SetScript("OnLeave", function(f)
        if ApplyVisuals then
            ApplyVisuals(f, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
    end)
    summaryHeader:Show()
    yOffset = yOffset + summaryHeaderH + 2

    if summaryExpanded then
        local summaryRowH = 26
        for si = 1, #filteredPlans do
            local ok, result = pcall(function()
                local sPlan = filteredPlans[si]
                local sClassColor = RAID_CLASS_COLORS[sPlan.characterClass or "PRIEST"] or {r = 1, g = 1, b = 1}

                local sTotalAll, sCompletedAll = 0, 0
                for _, catInfo in ipairs(CATEGORIES) do
                    if sPlan.questTypes and sPlan.questTypes[catInfo.key] then
                        local c, t = GetCategoryStats(sPlan, catInfo.key)
                        sCompletedAll = sCompletedAll + c
                        sTotalAll = sTotalAll + t
                    end
                end

                local sRow = CreateCard(parent, summaryRowH)
                sRow:SetPoint("TOPLEFT", 10, -yOffset)
                sRow:SetPoint("TOPRIGHT", -10, -yOffset)

                local sAccent = sRow:CreateTexture(nil, "ARTWORK")
                sAccent:SetSize(3, summaryRowH - 4)
                sAccent:SetPoint("LEFT", 4, 0)
                sAccent:SetColorTexture(sClassColor.r, sClassColor.g, sClassColor.b, 0.9)

                local sName = FontManager:CreateFontString(sRow, "body", "OVERLAY")
                sName:SetPoint("LEFT", 14, 0)
                sName:SetWidth(width * 0.25)
                sName:SetJustifyH("LEFT")
                sName:SetWordWrap(false)
                sName:SetText(string.format("|cff%02x%02x%02x%s|r",
                    sClassColor.r * 255, sClassColor.g * 255, sClassColor.b * 255,
                    sPlan.characterName or "Unknown"))

                -- Per-category mini progress
                local catX = width * 0.30
                for _, catInfo in ipairs(CATEGORIES) do
                    if sPlan.questTypes and sPlan.questTypes[catInfo.key] then
                        local display = CAT_DISPLAY[catInfo.key] or {}
                        local catColor = display.color or {0.8, 0.8, 0.8}
                        local c, t = GetCategoryStats(sPlan, catInfo.key)
                        if t > 0 then
                            local catFs = FontManager:CreateFontString(sRow, "small", "OVERLAY")
                            catFs:SetPoint("LEFT", catX, 0)
                            local cColor = (c == t) and "|cff44ff44" or string.format("|cff%02x%02x%02x", catColor[1] * 255, catColor[2] * 255, catColor[3] * 255)
                            catFs:SetText(cColor .. c .. "/" .. t .. "|r")
                            catX = catX + 48
                        end
                    end
                end

                -- Total progress on right
                local sTotalFs = FontManager:CreateFontString(sRow, "body", "OVERLAY")
                sTotalFs:SetPoint("RIGHT", -12, 0)
                local sTotalColor = (sTotalAll > 0 and sCompletedAll == sTotalAll) and "|cff44ff44" or "|cffffcc00"
                sTotalFs:SetText(sTotalColor .. sCompletedAll .. "/" .. sTotalAll .. "|r")

                -- Vault mini-progress (if character has a vault plan)
                local vaultPlan = self:HasActiveWeeklyPlan(sPlan.characterName, sPlan.characterRealm)
                if vaultPlan and vaultPlan.slots then
                    local tracked = vaultPlan.trackedSlots or { dungeon = true, raid = true, world = true }
                    local vaultParts = {}
                    local slotDefs = {
                        { key = "dungeon", label = "M+", prog = vaultPlan.progress and vaultPlan.progress.dungeonCount or 0, max = 8 },
                        { key = "raid",    label = "R",  prog = vaultPlan.progress and vaultPlan.progress.raidBossCount or 0, max = 6 },
                        { key = "world",   label = "W",  prog = vaultPlan.progress and vaultPlan.progress.worldActivityCount or 0, max = 8 },
                    }
                    for _, sd in ipairs(slotDefs) do
                        if tracked[sd.key] then
                            local vColor = (sd.prog >= sd.max) and "|cff44ff44" or "|cffffcc00"
                            vaultParts[#vaultParts + 1] = sd.label .. ":" .. vColor .. sd.prog .. "|r"
                        end
                    end
                    if #vaultParts > 0 then
                        local vaultFs = FontManager:CreateFontString(sRow, "small", "OVERLAY")
                        vaultFs:SetPoint("RIGHT", sTotalFs, "LEFT", -14, 0)
                        vaultFs:SetTextColor(0.7, 0.7, 0.7)
                        vaultFs:SetText(table.concat(vaultParts, " "))
                    end
                end

                sRow:Show()
                return summaryRowH + 2
            end)
            if ok and result then
                yOffset = yOffset + result
            else
                yOffset = yOffset + summaryRowH + 2
            end
        end
        yOffset = yOffset + 4
    end

    yOffset = yOffset + 4

    -- ===== PER-CHARACTER DETAIL SECTIONS =====
    for pi = 1, #filteredPlans do
        local plan = filteredPlans[pi]
        local classColor = RAID_CLASS_COLORS[plan.characterClass or "PRIEST"] or {r = 1, g = 1, b = 1}

        -- Character header card
        local totalAll, completedAll = 0, 0
        for _, catInfo in ipairs(CATEGORIES) do
            if plan.questTypes and plan.questTypes[catInfo.key] then
                local c, t = GetCategoryStats(plan, catInfo.key)
                completedAll = completedAll + c
                totalAll = totalAll + t
            end
        end

        local headerH = 56
        local headerCard = CreateCard(parent, headerH)
        headerCard:SetPoint("TOPLEFT", 10, -yOffset)
        headerCard:SetPoint("TOPRIGHT", -10, -yOffset)

        -- Class-colored left accent bar
        local accentBar = headerCard:CreateTexture(nil, "ARTWORK")
        accentBar:SetSize(3, headerH - 8)
        accentBar:SetPoint("LEFT", 4, 0)
        accentBar:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.9)

        -- Character name
        local charName = FontManager:CreateFontString(headerCard, "header", "OVERLAY")
        charName:SetPoint("LEFT", 14, 10)
        charName:SetText(string.format(
            "|cff%02x%02x%02x%s|r |cff888888-%s|r",
            classColor.r * 255, classColor.g * 255, classColor.b * 255,
            plan.characterName or "Unknown",
            plan.characterRealm or ""
        ))

        -- Progress text
        local progressText = FontManager:CreateFontString(headerCard, "body", "OVERLAY")
        progressText:SetPoint("LEFT", 14, -16)
        local pctColor = (totalAll > 0 and completedAll == totalAll) and "|cff44ff44" or "|cffffcc00"
        progressText:SetText(string.format(
            "%s%d/%d|r %s",
            pctColor, completedAll, totalAll,
            (ns.L and ns.L["CONTENT_MIDNIGHT"]) or "Midnight"
        ))

        -- Remove button (larger for easier clicking)
        local removeBtn = ns.UI.Factory:CreateButton(headerCard, 24, 24, true)
        removeBtn:SetPoint("RIGHT", -12, 0)
        removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        removeBtn:SetScript("OnClick", function()
            self:RemovePlan(plan.id)
            if self.RefreshUI then self:RefreshUI() end
        end)

        headerCard:Show()
        yOffset = yOffset + headerH + 6

        -- Quest category sections
        for _, catInfo in ipairs(CATEGORIES) do
            local catKey = catInfo.key
            if plan.questTypes and plan.questTypes[catKey] then
                local questList = (plan.quests and plan.quests[catKey]) or {}
                local showCategory = #questList > 0
                if showCategory then
                    local display = CAT_DISPLAY[catKey] or {}
                    local catColor = display.color or {0.8, 0.8, 0.8}
                    local catName = display.name and display.name() or catKey

                    local completed, total = GetCategoryStats(plan, catKey)
                    local groupKey = "dq_" .. tostring(plan.id) .. "_" .. catKey
                    local isExpanded = (expandedGroups[groupKey] ~= false)

                    -- Category header
                    local catCard = CreateCard(parent, CAT_HEADER_H)
                    catCard:SetPoint("TOPLEFT", 10, -yOffset)
                    catCard:SetPoint("TOPRIGHT", -10, -yOffset)
                    catCard:EnableMouse(true)

                    -- Category color indicator
                    local catAccent = catCard:CreateTexture(nil, "ARTWORK")
                    catAccent:SetSize(3, CAT_HEADER_H - 6)
                    catAccent:SetPoint("LEFT", 4, 0)
                    catAccent:SetColorTexture(catColor[1], catColor[2], catColor[3], 0.9)

                    -- Arrow (atlas-based, matching CreateCollapsibleHeader)
                    local expandIcon = catCard:CreateTexture(nil, "ARTWORK")
                    expandIcon:SetSize(16, 16)
                    expandIcon:SetPoint("LEFT", 10, 0)
                    if isExpanded then
                        expandIcon:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", false)
                    else
                        expandIcon:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", false)
                    end
                    expandIcon:SetVertexColor(catColor[1], catColor[2], catColor[3])

                    -- Category name
                    local catLabel = FontManager:CreateFontString(catCard, "body", "OVERLAY")
                    catLabel:SetPoint("LEFT", 30, 0)
                    catLabel:SetTextColor(catColor[1], catColor[2], catColor[3])
                    catLabel:SetText(catName)

                    -- Count
                    local countLabel = FontManager:CreateFontString(catCard, "body", "OVERLAY")
                    countLabel:SetPoint("RIGHT", -12, 0)
                    local countColor = (completed == total and total > 0) and "|cff44ff44" or "|cffffffff"
                    countLabel:SetText(countColor .. completed .. "/" .. total .. "|r")

                    catCard:SetScript("OnMouseDown", function()
                        if ns.UI_SetExpandedGroup then
                            ns.UI_SetExpandedGroup(groupKey, not isExpanded)
                        elseif expandedGroups then
                            expandedGroups[groupKey] = not isExpanded
                        end
                        if self.RefreshUI then self:RefreshUI() end
                    end)
                    catCard:SetScript("OnEnter", function(self)
                        if ApplyVisuals then
                            ApplyVisuals(self, {0.10, 0.10, 0.12, 1}, {catColor[1], catColor[2], catColor[3], 0.6})
                        end
                    end)
                    catCard:SetScript("OnLeave", function(self)
                        if ApplyVisuals then
                            ApplyVisuals(self, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
                        end
                    end)

                    catCard:Show()
                    yOffset = yOffset + CAT_HEADER_H + 2

                    -- Quest rows (when expanded)
                    if isExpanded then
                        if #questList > 0 then
                            for qi = 1, #questList do
                                local quest = questList[qi]
                                local isSub = quest.isSubQuest
                                local leftIndent = isSub and 26 or 14
                                local iconSize = isSub and 12 or 14

                                -- Assignment rows with objectives get extra height
                                local hasObjectives = (catKey == "assignments" and quest.objectives and #quest.objectives > 0 and not quest.isComplete)
                                local rowH = hasObjectives and (ROW_H + #quest.objectives * 16) or ROW_H

                                local row
                                row, yOffset = ns.UI.Factory:CreateDataRow(parent, yOffset, qi, rowH)
                                row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -yOffset + rowH)
                                row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -yOffset + rowH)
                                row:EnableMouse(true)

                                -- Status icon (atlas-based)
                                local statusIcon = row:CreateTexture(nil, "ARTWORK")
                                statusIcon:SetSize(iconSize, iconSize)
                                if hasObjectives then
                                    statusIcon:SetPoint("TOPLEFT", leftIndent, -6)
                                else
                                    statusIcon:SetPoint("LEFT", leftIndent, 0)
                                end
                                if quest.isComplete then
                                    statusIcon:SetAtlas("common-icon-checkmark", false)
                                    statusIcon:SetVertexColor(0.27, 1, 0.27)
                                elseif quest.isLocked then
                                    statusIcon:SetAtlas("Padlock", false)
                                    statusIcon:SetVertexColor(1, 0.6, 0.2)
                                else
                                    statusIcon:SetAtlas("Objective-Nub", false)
                                    statusIcon:SetVertexColor(0.6, 0.6, 0.6)
                                end

                                -- Quest title
                                local titleFs = FontManager:CreateFontString(row, isSub and "small" or "body", "OVERLAY")
                                if hasObjectives then
                                    titleFs:SetPoint("TOPLEFT", leftIndent + iconSize + 4, -4)
                                else
                                    titleFs:SetPoint("LEFT", leftIndent + iconSize + 4, 0)
                                end
                                titleFs:SetWidth(width * 0.50)
                                titleFs:SetJustifyH("LEFT")
                                titleFs:SetWordWrap(false)
                                if quest.isComplete then
                                    titleFs:SetText("|cff44ff44" .. (quest.title or "") .. "|r")
                                elseif quest.isLocked then
                                    titleFs:SetText("|cffff9933" .. (quest.title or "") .. "|r")
                                elseif isSub then
                                    titleFs:SetText("|cffaaaaaa" .. (quest.title or "") .. "|r")
                                else
                                    titleFs:SetText("|cffffffff" .. (quest.title or "") .. "|r")
                                end

                                -- Assignment: show each objective with individual progress
                                if hasObjectives then
                                    local objY = -4
                                    for oi = 1, #quest.objectives do
                                        local obj = quest.objectives[oi]
                                        objY = objY - 16
                                        local objIcon = row:CreateTexture(nil, "ARTWORK")
                                        objIcon:SetSize(8, 8)
                                        objIcon:SetPoint("TOPLEFT", leftIndent + iconSize + 8, objY)
                                        if obj.finished then
                                            objIcon:SetAtlas("common-icon-checkmark", false)
                                            objIcon:SetVertexColor(0.27, 1, 0.27)
                                        else
                                            objIcon:SetAtlas("Objective-Nub", false)
                                            objIcon:SetVertexColor(0.5, 0.5, 0.5)
                                        end

                                        local objText = obj.text or string.format("Objective %d", oi)
                                        local objColor = obj.finished and "|cff44ff44" or "|cffaaaaaa"
                                        local objFs = FontManager:CreateFontString(row, "small", "OVERLAY")
                                        objFs:SetPoint("TOPLEFT", leftIndent + iconSize + 20, objY + 2)
                                        objFs:SetWidth(width * 0.45)
                                        objFs:SetJustifyH("LEFT")
                                        objFs:SetWordWrap(false)
                                        objFs:SetText(objColor .. objText .. "|r")

                                        local progFs = FontManager:CreateFontString(row, "small", "OVERLAY")
                                        progFs:SetPoint("TOPLEFT", leftIndent + iconSize + 20 + width * 0.46, objY + 2)
                                        progFs:SetJustifyH("LEFT")
                                        local progColor = obj.finished and "|cff44ff44" or "|cffffcc00"
                                        progFs:SetText(string.format("%s%d/%d|r", progColor, obj.numFulfilled, obj.numRequired))
                                    end

                                    -- Zone on the right side
                                    if quest.zone and quest.zone ~= "" then
                                        local zoneFs = FontManager:CreateFontString(row, "small", "OVERLAY")
                                        zoneFs:SetPoint("TOPRIGHT", -14, -6)
                                        zoneFs:SetJustifyH("RIGHT")
                                        zoneFs:SetText("|cff888888" .. quest.zone .. "|r")
                                    end
                                else
                                    -- Standard row: zone + time
                                    local zoneFs = FontManager:CreateFontString(row, "body", "OVERLAY")
                                    zoneFs:SetPoint("LEFT", 32 + width * 0.52, 0)
                                    zoneFs:SetWidth(width * 0.25)
                                    zoneFs:SetJustifyH("LEFT")
                                    zoneFs:SetWordWrap(false)
                                    zoneFs:SetText("|cffffffff" .. (quest.zone or "") .. "|r")

                                    if quest.timeLeft and quest.timeLeft > 0 then
                                        local timeFs = FontManager:CreateFontString(row, "body", "OVERLAY")
                                        timeFs:SetPoint("RIGHT", -14, 0)
                                        timeFs:SetText("|cffffffff" .. FormatTimeLeft(quest.timeLeft) .. "|r")
                                    end
                                end

                                AttachQuestRowTooltip(row, quest)
                            end
                        end
                        yOffset = yOffset + 4
                    end
                end
            end
        end

        yOffset = yOffset + 8
    end

    return yOffset
end

function WarbandNexus:DrawActivePlans(parent, yOffset, width, category)
    local plans = self:GetActivePlans()
    
    -- Filter by category first
    if category == "daily_tasks" then
        local dailyPlans = {}
        for _, plan in ipairs(plans) do
            if plan.type == "daily_quests" then
                dailyPlans[#dailyPlans + 1] = plan
            end
        end
        plans = dailyPlans
    elseif category == "active" then
        local activePlans = {}
        for _, plan in ipairs(plans) do
            activePlans[#activePlans + 1] = plan
        end
        plans = activePlans
    end
    
    -- Apply search filter (My Plans global search, skip for daily_tasks)
    if category ~= "daily_tasks" then
        local activeSearch = ns._plansActiveSearch
        if activeSearch and activeSearch ~= "" then
            local query = activeSearch:lower()
            local searchFiltered = {}
            for _, plan in ipairs(plans) do
                local resolvedName = (WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name or ""
                local name = resolvedName:lower()
                local source = (plan.resolvedSource or plan.source or ""):lower()
                local ptype = (plan.type or ""):lower()
                if name:find(query, 1, true) or source:find(query, 1, true) or ptype:find(query, 1, true) then
                    searchFiltered[#searchFiltered + 1] = plan
                end
            end
            plans = searchFiltered
        end
    end

    -- Sort plans: Weekly vault first, daily quests second, then others
    local typePriority = { weekly_vault = 1, daily_quests = 2 }
    table.sort(plans, function(a, b)
        local pa = typePriority[a.type] or 99
        local pb = typePriority[b.type] or 99
        if pa ~= pb then return pa < pb end
        local aID = tonumber(a.id) or 0
        local bID = tonumber(b.id) or 0
        return aID < bID
    end)

    -- Filter plans based on showCompleted flag (read from DB each time so toggle always applies)
    local showCompletedNow = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.plansShowCompleted or false
    local filteredPlans = {}
    for _, plan in ipairs(plans) do
        local isComplete = false
        
        if plan.type == "weekly_vault" then
            isComplete = plan.fullyCompleted == true
        elseif plan.type == "daily_quests" then
            local totalQuests = 0
            local completedQuests = 0
            for cat, questList in pairs(plan.quests or {}) do
                if plan.questTypes and plan.questTypes[cat] then
                    for _, quest in ipairs(questList) do
                        if not quest.isSubQuest then
                            totalQuests = totalQuests + 1
                            if quest.isComplete then
                                completedQuests = completedQuests + 1
                            end
                        end
                    end
                end
            end
            isComplete = (totalQuests > 0 and completedQuests == totalQuests)
        else
            local progress = self:GetResolvedPlanProgress(plan)
            isComplete = (progress and progress.collected) or (plan.completed == true)
        end
        
        if showCompletedNow then
            if isComplete then
                filteredPlans[#filteredPlans + 1] = plan
            end
        else
            if not isComplete then
                filteredPlans[#filteredPlans + 1] = plan
            end
        end
    end
    plans = filteredPlans

    if category == "daily_tasks" then
        return self:DrawDailyTasksView(parent, yOffset, width, plans)
    end
    
    if #plans == 0 then
        -- Empty state card using standardized factory
        local _, height = CreateEmptyStateCard(parent, "plans", yOffset)
        return yOffset + height + 10
    end
    
    -- === 2-COLUMN CARD GRID (matching browse view) ===
    local cardSpacing = 8
    local cardWidth = (width - cardSpacing) / 2
    local CARD_HEIGHT_DEFAULT = 105       -- Standard height for mount/pet/toy cards
    local CARD_HEIGHT_ACHIEVEMENT = 150   -- Achievement cards need more space (info + progress + requirements)
    
    -- Initialize CardLayoutManager for dynamic card positioning
    local layoutManager = CardLayoutManager:Create(parent, 2, cardSpacing, yOffset)
    
    -- Resize: defer layout refresh until resize ends (no continuous render during drag)
    if not parent._layoutManagerResizeHandler then
        local layoutResizeTimer = nil
        parent:SetScript("OnSizeChanged", function(self)
            if layoutResizeTimer then
                layoutResizeTimer:Cancel()
            end
            layoutResizeTimer = C_Timer.NewTimer(0.15, function()
                layoutResizeTimer = nil
                if layoutManager then
                    CardLayoutManager:RefreshLayout(layoutManager)
                end
            end)
        end)
        parent._layoutManagerResizeHandler = true
    end
    
    for i, plan in ipairs(plans) do
        local progress = self:GetResolvedPlanProgress(plan)
        
        -- === WEEKLY VAULT PLANS (Full Width Card via Factory) ===
        if plan.type == "weekly_vault" then
            local weeklyCardHeight = 170
            
            -- Create raw card (no base card - weekly vault is fully custom)
            local card = CreateCard(parent, weeklyCardHeight)
            card:EnableMouse(true)
            
            -- Add to layout manager
            local yPos = CardLayoutManager:AddCard(layoutManager, card, 0, weeklyCardHeight)
            
            -- Override positioning to make it full width
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 10, -yPos)
            card:SetPoint("TOPRIGHT", -10, -yPos)
            
            -- Update layout manager for full-width card
            layoutManager.currentYOffsets[0] = yPos + weeklyCardHeight + cardSpacing
            layoutManager.currentYOffsets[1] = yPos + weeklyCardHeight + cardSpacing
            
            -- Mark as full width
            card._layoutInfo = card._layoutInfo or {}
            card._layoutInfo.isFullWidth = true
            card._layoutInfo.yPos = yPos
            
            -- Apply accent border (My Plans cards)
            if ApplyVisuals then
                local borderColor = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 }
                ApplyVisuals(card, {0.08, 0.08, 0.10, 1}, borderColor)
            end
            
            -- Create weekly vault content via factory
            PlanCardFactory:CreateWeeklyVaultCard(card, plan, progress, nil)
            
            card:Show()
        
        -- === DAILY QUEST PLANS (Single Full-Width Card, vault-style) ===
        elseif plan.type == "daily_quests" then
            local questCardHeight = 170
            
            local card = CreateCard(parent, questCardHeight)
            card:EnableMouse(true)
            
            local yPos = CardLayoutManager:AddCard(layoutManager, card, 0, questCardHeight)
            
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 10, -yPos)
            card:SetPoint("TOPRIGHT", -10, -yPos)
            
            layoutManager.currentYOffsets[0] = yPos + questCardHeight + cardSpacing
            layoutManager.currentYOffsets[1] = yPos + questCardHeight + cardSpacing
            
            card._layoutInfo = card._layoutInfo or {}
            card._layoutInfo.isFullWidth = true
            card._layoutInfo.yPos = yPos
            
            if ApplyVisuals then
                local borderColor = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 }
                ApplyVisuals(card, {0.08, 0.08, 0.10, 1}, borderColor)
            end
            
            PlanCardFactory:CreateDailyQuestCard(card, plan)
            
            card:Show()
        
        else
            -- === REGULAR PLANS (2-Column Layout) ===
            
            -- Use provided width (Parent - 20) for consistent margins
            local listCardWidth = (width - cardSpacing) / 2
            
            -- Determine column (alternate between 0 and 1)
            -- CRITICAL: Count only regular plans (exclude weekly_vault and daily_quests from column calculation)
            local regularPlanIndex = 0
            for j = 1, i - 1 do
                if plans[j].type ~= "weekly_vault" and plans[j].type ~= "daily_quests" then
                    regularPlanIndex = regularPlanIndex + 1
                end
            end
            local col = regularPlanIndex % 2
        
        -- Per-type card height (achievements need more vertical space for collapsed content)
        local cardHeight = (plan.type == "achievement") and CARD_HEIGHT_ACHIEVEMENT or CARD_HEIGHT_DEFAULT
        
        -- Use factory to create card
        local card = nil
        if PlanCardFactory then
            card = PlanCardFactory:CreateCard(parent, plan, progress, layoutManager, col, cardHeight, listCardWidth)
        else
            -- Fallback to old method if factory not available
            card = CreateCard(parent, cardHeight)
        card:SetWidth(listCardWidth)
        card:EnableMouse(true)
        CardLayoutManager:AddCard(layoutManager, card, col, cardHeight)
        card.originalHeight = cardHeight
        end
        
        if card then
            -- Remove button (X icon on top right) - Hide for completed plans
            if not (progress and progress.collected) then
                local CBL = ns.UI_CARD_BUTTON_LAYOUT or {ACTION_SIZE = 20, ACTION_MARGIN = 8, ACTION_GAP = 4}
                local actionSize = CBL.ACTION_SIZE
                local actionMargin = CBL.ACTION_MARGIN
                local actionGap = CBL.ACTION_GAP
                
                -- For custom plans, add a complete button (green checkmark) before the X
                if plan.type == "custom" then
                    local completeBtn = ns.UI.Factory:CreateButton(card, actionSize, actionSize, true)  -- noBorder=true
                    completeBtn:SetPoint("TOPRIGHT", -(actionMargin + actionSize + actionGap), -actionMargin)
                    completeBtn:SetNormalTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    completeBtn:SetHighlightTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    completeBtn:GetHighlightTexture():SetAlpha(0.5)
                    completeBtn:SetScript("OnClick", function()
                        if self.CompleteCustomPlan then
                            self:CompleteCustomPlan(plan.id)
                            -- Immediate refresh since event may be deferred
                            if self.RefreshUI then self:RefreshUI() end
                        end
                    end)
                    completeBtn:SetScript("OnEnter", function(btn)
                        ns.TooltipService:Show(btn, { type = "custom", title = "Complete the Plan", icon = false, anchor = "ANCHOR_TOP", lines = {} })
                    end)
                    completeBtn:SetScript("OnLeave", function() ns.TooltipService:Hide() end)
                end
                
                local removeBtn = ns.UI.Factory:CreateButton(card, actionSize, actionSize, true)  -- noBorder=true
                removeBtn:SetPoint("TOPRIGHT", -actionMargin, -actionMargin)
                removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
                removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
                -- Mark that click was on remove button to prevent card expansion
                removeBtn:SetScript("OnMouseDown", function(self, button)
                    if card then
                        card.clickedOnRemoveBtn = true
                    end
                end)
                removeBtn:SetScript("OnClick", function()
                    self:RemovePlan(plan.id)
                    if self.RefreshUI then self:RefreshUI() end
                end)
                removeBtn:SetScript("OnEnter", function(btn)
                    ns.TooltipService:Show(btn, { type = "custom", title = "Delete the Plan", icon = false, anchor = "ANCHOR_TOP", lines = {} })
                end)
                removeBtn:SetScript("OnLeave", function() ns.TooltipService:Hide() end)
                
                local hasReminder = self.HasPlanReminder and self:HasPlanReminder(plan.id)
                local alertBtnX = -(actionMargin + actionSize + actionGap)
                if plan.type == "custom" then
                    alertBtnX = -(actionMargin + (actionSize + actionGap) * 2)
                end
                local alertBtn = ns.UI.Factory:CreateButton(card, actionSize, actionSize, true)
                alertBtn:SetPoint("TOPRIGHT", alertBtnX, -actionMargin)
                local bellTex = alertBtn:CreateTexture(nil, "ARTWORK")
                bellTex:SetSize(actionSize - 2, actionSize - 2)
                bellTex:SetPoint("CENTER")
                bellTex:SetAtlas("minimap-genericevent-hornicon-small", true)
                if hasReminder then
                    bellTex:SetVertexColor(1, 0.82, 0)
                else
                    bellTex:SetVertexColor(0.5, 0.5, 0.5)
                end
                alertBtn._bellTex = bellTex
                alertBtn:SetScript("OnMouseDown", function(self, button)
                    if card then card.clickedOnRemoveBtn = true end
                end)
                alertBtn:SetScript("OnClick", function()
                    if self.ShowSetAlertDialog then
                        self:ShowSetAlertDialog(plan.id)
                    end
                end)
                alertBtn:SetScript("OnEnter", function(btn)
                    if btn._bellTex then btn._bellTex:SetVertexColor(1, 0.9, 0.3) end
                    local title = hasReminder and ((ns.L and ns.L["ALERT_ACTIVE"]) or "Alert Active") or ((ns.L and ns.L["SET_ALERT"]) or "Set Alert")
                    ns.TooltipService:Show(btn, { type = "custom", title = title, icon = false, anchor = "ANCHOR_TOP", lines = {} })
                end)
                alertBtn:SetScript("OnLeave", function(btn)
                    if btn._bellTex then
                        local active = self.HasPlanReminder and self:HasPlanReminder(plan.id)
                        btn._bellTex:SetVertexColor(active and 1 or 0.5, active and 0.82 or 0.5, active and 0 or 0.5)
                    end
                    ns.TooltipService:Hide()
                end)

                -- Adjust nameText right anchor to avoid overlap with action buttons
                if card.nameText then
                    local nameRightOffset = alertBtnX - actionSize - 2
                    local pt1, rel1, relPt1, x1, y1 = card.nameText:GetPoint(1)
                    card.nameText:ClearAllPoints()
                    if pt1 and rel1 then
                        card.nameText:SetPoint(pt1, rel1, relPt1, x1, y1)
                    end
                    card.nameText:SetPoint("RIGHT", card, "RIGHT", nameRightOffset, 0)
                end
            end

            -- Right-click context menu (try count only for drop-source; reset cycle for custom)
            local tryCountTypes = { mount = true, pet = true, toy = true, illusion = true }
            local hasTryCount = tryCountTypes[plan.type]
            if hasTryCount then
                local id = plan.mountID or plan.speciesID or plan.itemID or plan.illusionID or plan.sourceID
                if not id or (WarbandNexus.IsDropSourceCollectible and not WarbandNexus:IsDropSourceCollectible(plan.type, id)) or (WarbandNexus.IsGuaranteedCollectible and WarbandNexus:IsGuaranteedCollectible(plan.type, id)) then
                    hasTryCount = false
                end
            end
            local hasResetCycle = plan.type == "custom"

            if hasTryCount or hasResetCycle then
                card:SetScript("OnMouseDown", function(_, button)
                    if button == "RightButton" and not card.clickedOnRemoveBtn then
                        local contextPlan = plan
                        
                        MenuUtil.CreateContextMenu(card, function(_, rootDescription)
                            if hasTryCount then
                                rootDescription:CreateButton(ns.L and ns.L["SET_TRY_COUNT"] or "Set Try Count", function()
                                    if contextPlan then
                                        local id = contextPlan.mountID or contextPlan.speciesID or contextPlan.itemID or contextPlan.illusionID or contextPlan.sourceID
                                        if id then
                                            ShowTryCountPopup(contextPlan, id)
                                        end
                                    end
                                end)
                            end
                            if hasResetCycle then
                                local rc = contextPlan.resetCycle
                                local resetSubmenu = rootDescription:CreateButton((ns.L and ns.L["SET_RESET_CYCLE"]) or "Set Reset Cycle")
                                
                                resetSubmenu:CreateRadio(
                                    (ns.L and ns.L["DAILY_RESET"]) or "Daily Reset",
                                    function() return rc and rc.enabled and rc.resetType == "daily" end,
                                    function()
                                        if contextPlan then
                                            local oldTotal = (contextPlan.resetCycle and contextPlan.resetCycle.totalCycles) or 7
                                            local oldRemaining = (contextPlan.resetCycle and contextPlan.resetCycle.remainingCycles) or oldTotal
                                            contextPlan.resetCycle = { enabled = true, resetType = "daily", lastResetTime = time(), totalCycles = oldTotal, remainingCycles = oldRemaining }
                                            if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
                                        end
                                    end
                                )
                                
                                resetSubmenu:CreateRadio(
                                    (ns.L and ns.L["WEEKLY_RESET"]) or "Weekly Reset",
                                    function() return rc and rc.enabled and rc.resetType == "weekly" end,
                                    function()
                                        if contextPlan then
                                            local oldTotal = (contextPlan.resetCycle and contextPlan.resetCycle.totalCycles) or 4
                                            local oldRemaining = (contextPlan.resetCycle and contextPlan.resetCycle.remainingCycles) or oldTotal
                                            contextPlan.resetCycle = { enabled = true, resetType = "weekly", lastResetTime = time(), totalCycles = oldTotal, remainingCycles = oldRemaining }
                                            if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
                                        end
                                    end
                                )
                                
                                resetSubmenu:CreateRadio(
                                    (ns.L and ns.L["NONE_DISABLE"]) or "None (Disable)",
                                    function() return not rc or not rc.enabled end,
                                    function()
                                        if contextPlan and contextPlan.resetCycle then
                                            contextPlan.resetCycle.enabled = false
                                            if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
                                        end
                                    end
                                )
                                
                                -- Extend Duration (only if active reset cycle)
                                if rc and rc.enabled and rc.totalCycles then
                                    local extUnit = rc.resetType == "daily" and ((ns.L and ns.L["DAYS_LABEL"]) or "days") or ((ns.L and ns.L["WEEKS_LABEL"]) or "weeks")
                                    local extendSubmenu = rootDescription:CreateButton((ns.L and ns.L["EXTEND_DURATION"]) or "Extend Duration")
                                    
                                    for _, amount in ipairs({1, 3, 7, 14}) do
                                        extendSubmenu:CreateButton(string.format("+%d %s", amount, extUnit), function()
                                            if contextPlan and contextPlan.resetCycle then
                                                contextPlan.resetCycle.totalCycles = (contextPlan.resetCycle.totalCycles or 0) + amount
                                                contextPlan.resetCycle.remainingCycles = (contextPlan.resetCycle.remainingCycles or 0) + amount
                                                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
                                            end
                                        end)
                                    end
                                end
                            end
                        end)
                    end
                    card.clickedOnRemoveBtn = nil
                end)
            end
            
            -- CRITICAL: Show the regular plan card!
            card:Show()
        end  -- End if card check
        end  -- End of regular plans (else block)
    end
    
    -- Sync row offsets after all cards are added (prevents gaps from mixed-height cards)
    CardLayoutManager:RecalculateAllPositions(layoutManager)
    
    -- Get final Y offset from layout manager
    local finalYOffset = CardLayoutManager:GetFinalYOffset(layoutManager)
    
    return finalYOffset
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

--[[
    Handle WN_PLANS_UPDATED event
    Only refreshes if Plans tab is visible (event-driven, no polling)
]]
function WarbandNexus:OnPlansUpdated(event, data)
    if not data or not data.action then return end
    
    -- Only refresh if Plans tab is currently visible
    if self:IsStillOnTab("plans") then
        self:RefreshUI()
    end
end


-- ============================================================================
-- BROWSER (Mounts, Pets, Toys, Recipes)
-- ============================================================================

function WarbandNexus:DrawBrowser(parent, yOffset, width, category)
    
    -- Use SharedWidgets search bar (like Items tab)
    -- Create results container that can be refreshed independently
    local resultsContainer = CreateResultsContainer(parent, yOffset + 40, 10)
    
    -- Create unique search ID for this category (e.g., "plans_mount", "plans_pet")
    local searchId = "plans_" .. (category or "unknown"):lower()
    local initialSearchText = SearchStateManager:GetQuery(searchId)
    
    local searchPlaceholder = string.format((ns.L and ns.L["SEARCH_CATEGORY_FORMAT"]) or "Search %s...", category)
    local searchContainer = CreateSearchBox(parent, width, searchPlaceholder, function(text)
        searchText = text
        
        -- Update search state via SearchStateManager (throttled, event-driven)
        SearchStateManager:SetSearchQuery(searchId, text)
        
        -- Prepare container for rendering
        if resultsContainer then
            SearchResultsRenderer:PrepareContainer(resultsContainer)
        end
        
        -- Redraw only results in the container
        local resultsYOffset = 0
        self:DrawBrowserResults(resultsContainer, resultsYOffset, width, category, text)
    end, 0.3, initialSearchText or searchText)
    searchContainer:SetPoint("TOPLEFT", 10, -yOffset)
    searchContainer:SetPoint("TOPRIGHT", -10, -yOffset)
    
    yOffset = yOffset + 40
    
    -- Initial draw of results
    local resultsYOffset = 0
    local actualResultsHeight = self:DrawBrowserResults(resultsContainer, resultsYOffset, width, category, searchText)
    
    return yOffset + (actualResultsHeight or 1800)  -- Use actual height with 1800 fallback
end

-- ============================================================================
-- ACHIEVEMENTS TABLE RENDERING
-- ============================================================================

--[[
    Helper function to create a single achievement row (unified for all hierarchy levels)
    @param parent Frame - Parent container
    @param achievement table - Achievement data
    @param yOffset number - Y offset for positioning
    @param width number - Row width
    @param indent number - Left indent (for hierarchy levels)
    @param animIdx number - Animation index for stagger
    @param shouldAnimate boolean - Whether to animate appearance
    @param expandedGroups table - Expand state storage
    @return number - New yOffset after row is drawn
]]
local function RenderAchievementRow(WarbandNexus, parent, achievement, yOffset, width, indent, animIdx, shouldAnimate, expandedGroups)
    local COLORS = ns.UI_COLORS
    local rowKey = "achievement_row_" .. achievement.id
    local rowExpanded = expandedGroups[rowKey] or false
    
    -- PERFORMANCE: Only compute criteria/reward details when row is expanded
    -- This avoids expensive C API calls (GetAchievementCriteriaInfo × N criteria) for collapsed rows
    -- When user expands a row, RefreshUI is called and this will recompute with rowExpanded=true
    local informationText = ""
    local requirementsText = ""
    local criteriaDetails = nil  -- Structured criteria data (populated when expanded)
    
    if rowExpanded then
        -- Get FRESH criteria count from API (only when expanded)
        local freshNumCriteria = GetAchievementNumCriteria(achievement.id)
        
        -- Build Information section
        if achievement.description and achievement.description ~= "" then
            informationText = FormatTextNumbers(achievement.description)
        end
        
        -- Get achievement rewards (title, mount, pet, toy, transmog)
        local rewardInfo = WarbandNexus:GetAchievementRewardInfo(achievement.id)
        if rewardInfo then
            if informationText ~= "" then
                informationText = informationText .. "\n\n"
            end
            
            local rewardLabel = (ns.L and ns.L["REWARD_LABEL"]) or "Reward:"
            if rewardInfo.type == "title" then
                local titleLabel = (ns.L and ns.L["TYPE_TITLE"]) or "Title"
                informationText = informationText .. "|cffffcc00" .. rewardLabel .. "|r " .. titleLabel .. " - |cff00ff00" .. rewardInfo.title .. "|r"
            elseif rewardInfo.itemName then
                local itemTypeText = rewardInfo.type:gsub("^%l", string.upper) -- Capitalize
                informationText = informationText .. "|cffffcc00" .. rewardLabel .. "|r " .. itemTypeText .. " - |cff00ff00" .. rewardInfo.itemName .. "|r"
            end
        elseif achievement.rewardText and achievement.rewardText ~= "" then
            if informationText ~= "" then
                informationText = informationText .. "\n\n"
            end
            local rewardLabel = (ns.L and ns.L["REWARD_LABEL"]) or "Reward:"
            informationText = informationText .. "|cffffcc00" .. rewardLabel .. "|r " .. FormatTextNumbers(achievement.rewardText)
        end
        
        if informationText == "" then
            informationText = "|cffffffff" .. ((ns.L and ns.L["NO_ADDITIONAL_INFO"]) or "No additional information") .. "|r"
        end
        
        -- Build Requirements section (expensive: iterates all criteria)
        local CRITERIA_TYPE_ACHIEVEMENT = 8
        if freshNumCriteria and freshNumCriteria > 0 then
            local completedCount = 0
            criteriaDetails = {}
            
            for criteriaIndex = 1, freshNumCriteria do
                local criteriaName, criteriaType, completed, quantity, reqQuantity, charName, flags, assetID, quantityString = GetAchievementCriteriaInfo(achievement.id, criteriaIndex)
                if criteriaName and criteriaName ~= "" then
                    if completed then
                        completedCount = completedCount + 1
                    end
                    
                    local statusIcon = completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t" or "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
                    local progressText = ""
                    
                    if quantity and reqQuantity and reqQuantity > 1 then
                        local P = ns.PLAN_UI_COLORS or {}
                        local progressColor = completed and (P.completed or "|cff44ff44") or (P.incomplete or "|cffffffff")
                        progressText = string.format(" %s(%s / %s)|r", progressColor, FormatNumber(quantity), FormatNumber(reqQuantity))
                    end
                    
                    -- Detect achievement-type criteria (criteriaType 8 = another achievement)
                    local linkedAchievementID = nil
                    if criteriaType == CRITERIA_TYPE_ACHIEVEMENT and assetID and assetID > 0 then
                        linkedAchievementID = assetID
                    end
                    
                    local P = ns.PLAN_UI_COLORS or {}
                    local textColor
                    if linkedAchievementID then
                        textColor = completed and "|cff44ddff" or "|cff44bbff"
                    else
                        textColor = completed and (P.completed or "|cff44ff44") or (P.incomplete or "|cffffffff")
                    end
                    
                    local formattedCriteriaName = FormatTextNumbers(criteriaName)
                    -- Append (Planned) for linked achievements that are in plans
                    local plannedSuffix = ""
                    if linkedAchievementID and WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(linkedAchievementID) then
                        local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
                        plannedSuffix = " |cffffcc00(" .. plannedWord .. ")|r"
                    end
                    table.insert(criteriaDetails, {
                        text = statusIcon .. " " .. textColor .. formattedCriteriaName .. "|r" .. progressText .. plannedSuffix,
                        linkedAchievementID = linkedAchievementID,
                        completed = completed,
                    })
                end
            end
            
            if #criteriaDetails > 0 then
                local progressPercent = math.floor((completedCount / freshNumCriteria) * 100)
                local P2 = ns.PLAN_UI_COLORS or {}
                local progressColor = (completedCount == freshNumCriteria) and (P2.progressFull or "|cff00ff00") or (P2.incomplete or "|cffffffff")
                local progressLine = string.format("%s%s of %s (%s%%)|r", progressColor, FormatNumber(completedCount), FormatNumber(freshNumCriteria), FormatNumber(progressPercent))
                
                -- Build legacy text for backwards compatibility
                local legacyLines = {}
                for _, cd in ipairs(criteriaDetails) do
                    table.insert(legacyLines, cd.text)
                end
                requirementsText = progressLine .. "\n" .. table.concat(legacyLines, "\n")
            else
                requirementsText = "|cffffffff" .. ((ns.L and ns.L["NO_CRITERIA_FOUND"]) or "No criteria found") .. "|r"
            end
        else
            requirementsText = "|cffffffff" .. ((ns.L and ns.L["NO_REQUIREMENTS_INSTANT"]) or "No requirements (instant completion)") .. "|r"
        end
    end
    
    -- Prepare row data for CreateExpandableRow
    local achievementTitle = FormatTextNumbers(achievement.name)
    if achievement.isPlanned then
        local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
        achievementTitle = achievementTitle .. " |cffffcc00(" .. plannedWord .. ")|r"
    end
    -- Criteria bölümü sadece en az bir kriter varsa göster
    local rowData = {
        icon = achievement.icon,
        score = achievement.points,
        title = achievementTitle,
        information = informationText,
        criteria = (criteriaDetails and #criteriaDetails > 0) and requirementsText or nil,
        criteriaData = (criteriaDetails and #criteriaDetails > 0) and criteriaDetails or nil,
    }
    
    -- Create expandable row using factory
    local row = CreateExpandableRow(
        parent,
        width - indent,
        32,
        rowData,
        rowExpanded,
        function(expanded)
            expandedGroups[rowKey] = expanded
            -- CRITICAL: Must call RefreshUI to reposition other rows
            -- PERFORMANCE: Debounce to batch rapid toggle clicks (16ms ≈ 1 frame)
            if WarbandNexus._achieveToggleTimer then WarbandNexus._achieveToggleTimer:Cancel() end
            WarbandNexus._achieveToggleTimer = C_Timer.NewTimer(0.016, function()
                WarbandNexus._achieveToggleTimer = nil
                WarbandNexus:RefreshUI()
            end)
        end
    )
    
    -- Set alternating colors (using standard UI_LAYOUT colors)
    if animIdx % 2 == 0 then
        row.bgColor = GetLayout().ROW_COLOR_EVEN
    else
        row.bgColor = GetLayout().ROW_COLOR_ODD
    end
    
    -- Re-apply visuals with correct colors
    if ApplyVisuals then
        local borderColor = {COLORS.accent[1] * 0.8, COLORS.accent[2] * 0.8, COLORS.accent[3] * 0.8, 0.4}
        ApplyVisuals(row.headerFrame, row.bgColor, borderColor)
    end
    
    row:SetPoint("TOPLEFT", indent, -yOffset)
    
    -- Animation
    if shouldAnimate then
        row:SetAlpha(0)
        C_Timer.After(animIdx * 0.02, function()
            if row and row.SetAlpha then
                UIFrameFadeIn(row, 0.2, row:GetAlpha(), 1)
            end
        end)
    end
    
    -- Add "+ Add" button or localized "Added" indicator (using Factory)
    local PlanCardFactory = ns.UI_PlanCardFactory
    local rightHeaderWidget = nil
    
    if achievement.isPlanned then
        row.addedIndicator = PlanCardFactory.CreateAddedIndicator(row.headerFrame, {
            buttonType = "row",
            label = (ns.L and ns.L["ADDED"]) or "Added",
            fontCategory = "body"
        })
        rightHeaderWidget = row.addedIndicator
    else
        local addBtn = PlanCardFactory.CreateAddButton(row.headerFrame, {
            buttonType = "row",
            onClick = function(btn)
                btn.achievementData = achievement
                WarbandNexus:AddPlan({
                    type = PLAN_TYPES.ACHIEVEMENT,
                    achievementID = achievement.id,
                    name = achievement.name,
                    icon = achievement.icon,
                    points = achievement.points,
                    source = achievement.source
                })
                
                -- Hide button and show localized "Added" indicator
                btn:Hide()
                row.addedIndicator = PlanCardFactory.CreateAddedIndicator(row.headerFrame, {
                    buttonType = "row",
                    label = (ns.L and ns.L["ADDED"]) or "Added",
                    fontCategory = "body"
                })
                
                -- Update achievement flag
                achievement.isPlanned = true
                
                -- Refresh UI (will update all other instances)
                WarbandNexus:RefreshUI()
            end
        })
        rightHeaderWidget = addBtn
    end
    
    -- Track button (Blizzard achievement tracker via centralized PlansManager helpers)
    local function IsAchievementTracked(achievementID)
        if WarbandNexus and WarbandNexus.IsAchievementTracked then
            return WarbandNexus:IsAchievementTracked(achievementID)
        end
        return false
    end
    local function ToggleTrack(achievementID)
        if not achievementID then return end
        if WarbandNexus and WarbandNexus.ToggleAchievementTracking then
            WarbandNexus:ToggleAchievementTracking(achievementID)
            return
        end
    end
    -- Track: Add ile aynı köşesiz stil (border/background yok)
    local trackBtn = ns.UI.Factory:CreateButton(row.headerFrame, 52, 20, true)
    trackBtn:SetPoint("RIGHT", rightHeaderWidget, "LEFT", -6, 0)
    trackBtn:SetFrameLevel(row.headerFrame:GetFrameLevel() + 10)
    trackBtn:SetScript("OnMouseDown", function() end)
    trackBtn:RegisterForClicks("AnyUp")
    local trackLabel = FontManager:CreateFontString(trackBtn, "body", "OVERLAY")
    trackLabel:SetPoint("CENTER")
    local trackedText = "|cff44ff44" .. ((ns.L and ns.L["TRACKED"]) or "Tracked") .. "|r"
    local trackText = "|cffffcc00" .. ((ns.L and ns.L["TRACK"]) or "Track") .. "|r"
    trackLabel:SetText(IsAchievementTracked(achievement.id) and trackedText or trackText)
    trackBtn:SetScript("OnEnter", function()
        if trackLabel then trackLabel:SetTextColor(0.6, 0.9, 1, 1) end
        GameTooltip:SetOwner(trackBtn, "ANCHOR_TOP")
        GameTooltip:SetText((ns.L and ns.L["TRACK_BLIZZARD_OBJECTIVES"]) or "Track in Blizzard objectives (max 10)")
        GameTooltip:Show()
    end)
    trackBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if trackLabel then trackLabel:SetText(IsAchievementTracked(achievement.id) and trackedText or trackText) end
    end)
    trackBtn:SetScript("OnClick", function()
        ToggleTrack(achievement.id)
        trackLabel:SetText(IsAchievementTracked(achievement.id) and trackedText or trackText)
    end)
    
    -- Return new yOffset (standard spacing: row height + betweenRows)
    return yOffset + row:GetHeight() + GetLayout().betweenRows
end

function WarbandNexus:DrawAchievementsTable(parent, results, yOffset, width, searchText)
    
    -- PERFORMANCE: Debounced refresh for header/row toggles
    -- Batches rapid toggle clicks into a single refresh (16ms ≈ 1 frame delay)
    local function DebouncedRefresh()
        if self._achieveToggleTimer then self._achieveToggleTimer:Cancel() end
        self._achieveToggleTimer = C_Timer.NewTimer(0.016, function()
            self._achieveToggleTimer = nil
            self:RefreshUI()
        end)
    end
    
    -- Normalize search text (passed from DrawBrowserResults)
    searchText = searchText or ""
    
    -- ===== EMPTY STATE =====
    if #results == 0 then
        -- Create unique search ID for this category
        local searchId = "plans_achievement"
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, searchText, searchId)
        SearchStateManager:UpdateResults(searchId, 0)
        return height
    end
    
    -- Get ALL achievement categories from WoW API (Blizzard order)
    local allCategoryIDs = GetCategoryList() or {}
    
    -- Build category data structure
    local categoryData = {} -- [categoryID] = { name, parentID, children = {}, achievements = {}, order = index }
    local rootCategories = {} -- Ordered list of root categories
    
    -- Initialize all categories from API with their order
    for index, categoryID in ipairs(allCategoryIDs) do
        local categoryName, parentCategoryID = GetCategoryInfo(categoryID)
        categoryData[categoryID] = {
            id = categoryID,
            name = categoryName or ((ns.L and ns.L["UNKNOWN_CATEGORY"]) or "Unknown Category"),
            parentID = parentCategoryID,
            children = {},
            achievements = {},
            order = index -- Preserve Blizzard order
        }
    end
    
    -- Build parent-child relationships (preserve order from API)
    for _, categoryID in ipairs(allCategoryIDs) do
        local data = categoryData[categoryID]
        if data then
            if data.parentID and data.parentID > 0 then
                -- This is a child category
                if categoryData[data.parentID] then
                    table.insert(categoryData[data.parentID].children, categoryID)
                end
            else
                -- This is a root category
                table.insert(rootCategories, categoryID)
            end
        end
    end
    
    -- Assign achievements to their categories
    for _, achievement in ipairs(results) do
        local categoryID = achievement.categoryID
        if categoryData[categoryID] then
            -- Update isPlanned flag for each achievement
            achievement.isPlanned = self:IsAchievementPlanned(achievement.id)
            table.insert(categoryData[categoryID].achievements, achievement)
        end
    end
    
    -- NOTE: We do NOT sort - we use API order (already in rootCategories and children arrays)
    
    -- Get expanded state
    local expandedGroups = ns.UI_GetExpandedGroups()
    
    -- Draw categories hierarchically
    for _, rootCategoryID in ipairs(rootCategories) do
        local rootCategory = categoryData[rootCategoryID]
        
        if rootCategory then
        -- Count total achievements in this root and its children (recursively)
        local totalAchievements = #rootCategory.achievements
        for _, childID in ipairs(rootCategory.children) do
            if categoryData[childID] then
                totalAchievements = totalAchievements + #categoryData[childID].achievements
                -- Also count grandchildren
                for _, grandchildID in ipairs(categoryData[childID].children or {}) do
                    if categoryData[grandchildID] then
                        totalAchievements = totalAchievements + #categoryData[grandchildID].achievements
                    end
                end
            end
        end
        
        -- Only draw root category if it has achievements (hide empty categories during search)
        if totalAchievements > 0 then
        -- Draw root category header
        local rootKey = "achievement_cat_" .. rootCategoryID
        local rootExpanded = self.achievementsExpandAllActive or (expandedGroups[rootKey] == true)
        
        -- Auto-expand if search is active
        if searchText and searchText ~= "" then
            rootExpanded = true
        end
        
        local rootHeader = CreateCollapsibleHeader(
            parent,
            string.format("%s (%s)", rootCategory.name, FormatNumber(totalAchievements)),
            rootKey,
            rootExpanded,
            function(expanded)
                expandedGroups[rootKey] = expanded
                if expanded then 
                    self.recentlyExpanded = self.recentlyExpanded or {}
                    self.recentlyExpanded[rootKey] = GetTime() 
                end
                DebouncedRefresh()
            end,
            "Interface\\Icons\\Achievement_General",
            false
        )
        rootHeader:SetPoint("TOPLEFT", 0, -yOffset)
        rootHeader:SetWidth(width)
        
        yOffset = yOffset + GetLayout().HEADER_HEIGHT
        
        -- Draw root category content if expanded
        if rootExpanded then
            local shouldAnimate = self.recentlyExpanded and self.recentlyExpanded[rootKey] and (GetTime() - self.recentlyExpanded[rootKey] < 0.5)
            local animIdx = 0
            
            -- Mini spacing after header (visual separation)
            yOffset = yOffset + 4
            
            -- Draw root's own achievements first (if any)
            for i, achievement in ipairs(rootCategory.achievements) do
                animIdx = animIdx + 1
                yOffset = RenderAchievementRow(self, parent, achievement, yOffset, width, GetLayout().BASE_INDENT, animIdx, shouldAnimate, expandedGroups)
            end
            
            -- Add spacing before child categories (if any exist)
            if #rootCategory.children > 0 and #rootCategory.achievements > 0 then
                yOffset = yOffset + SECTION_SPACING
            end
            
            -- Draw child categories (sub-categories)
            for childIdx, childID in ipairs(rootCategory.children) do
                local childCategory = categoryData[childID]
                
                -- Count achievements in this child and its children (grandchildren)
                local childAchievementCount = #childCategory.achievements
                for _, grandchildID in ipairs(childCategory.children or {}) do
                    if categoryData[grandchildID] then
                        childAchievementCount = childAchievementCount + #categoryData[grandchildID].achievements
                    end
                end
                
                -- Only draw child category if it has achievements (hide empty categories during search)
                if childAchievementCount > 0 then
                -- Draw sub-category header (indented)
                local childKey = "achievement_cat_" .. childID
                local childExpanded = self.achievementsExpandAllActive or (expandedGroups[childKey] == true)
                
                -- Auto-expand if search is active
                if searchText and searchText ~= "" then
                    childExpanded = true
                end
                
                local childHeader = CreateCollapsibleHeader(
                    parent,
                    string.format("%s (%s)", childCategory.name, FormatNumber(childAchievementCount)),
                    childKey,
                    childExpanded,
                    function(expanded)
                        expandedGroups[childKey] = expanded
                        if expanded then 
                            self.recentlyExpanded = self.recentlyExpanded or {}
                            self.recentlyExpanded[childKey] = GetTime() 
                        end
                        DebouncedRefresh()
                    end,
                    "Interface\\Icons\\Achievement_General",
                    false
                )
                childHeader:SetPoint("TOPLEFT", GetLayout().BASE_INDENT, -yOffset) -- Standard indent
                childHeader:SetWidth(width - GetLayout().BASE_INDENT)
                
                yOffset = yOffset + GetLayout().HEADER_HEIGHT
                
                -- Draw sub-category content if expanded
                if childExpanded then
                    -- Mini spacing after header (visual separation)
                    yOffset = yOffset + 4
                    
                    -- First, draw this category's own achievements
                    if #childCategory.achievements > 0 then
                        for i, achievement in ipairs(childCategory.achievements) do
                            animIdx = animIdx + 1
                            yOffset = RenderAchievementRow(self, parent, achievement, yOffset, width, GetLayout().BASE_INDENT * 2, animIdx, shouldAnimate, expandedGroups)
                        end
                    end
                    
                    -- Add spacing before grandchildren (if any exist)
                    if #(childCategory.children or {}) > 0 and #childCategory.achievements > 0 then
                        yOffset = yOffset + SECTION_SPACING
                    end
                    
                    -- Now draw grandchildren categories (3rd level: e.g., Quests > Eastern Kingdoms > Zone)
                    for grandchildIdx, grandchildID in ipairs(childCategory.children or {}) do
                        local grandchildCategory = categoryData[grandchildID]
                        if grandchildCategory and #grandchildCategory.achievements > 0 then
                            -- Draw grandchild category header (double indented)
                            local grandchildKey = "achievement_cat_" .. grandchildID
                            local grandchildExpanded = self.achievementsExpandAllActive or (expandedGroups[grandchildKey] == true)
                            
                            -- Auto-expand if search is active
                            if searchText and searchText ~= "" then
                                grandchildExpanded = true
                            end
                            
                            local grandchildHeader = CreateCollapsibleHeader(
                                parent,
                                string.format("%s (%s)", grandchildCategory.name, FormatNumber(#grandchildCategory.achievements)),
                                grandchildKey,
                                grandchildExpanded,
                                function(expanded)
                                    expandedGroups[grandchildKey] = expanded
                                    if expanded then 
                                        self.recentlyExpanded = self.recentlyExpanded or {}
                                        self.recentlyExpanded[grandchildKey] = GetTime() 
                                    end
                                    DebouncedRefresh()
                                end,
                                "Interface\\Icons\\Achievement_General",
                                false
                            )
                            grandchildHeader:SetPoint("TOPLEFT", GetLayout().BASE_INDENT * 2, -yOffset) -- Double indent (30px)
                            grandchildHeader:SetWidth(width - (GetLayout().BASE_INDENT * 2))
                            
                            yOffset = yOffset + GetLayout().HEADER_HEIGHT
                            
                            -- Draw grandchild achievements if expanded
                            if grandchildExpanded then
                                -- Mini spacing after header (visual separation)
                                yOffset = yOffset + 4
                                
                                for i, achievement in ipairs(grandchildCategory.achievements) do
                                    animIdx = animIdx + 1
                                    yOffset = RenderAchievementRow(self, parent, achievement, yOffset, width, GetLayout().BASE_INDENT * 3, animIdx, shouldAnimate, expandedGroups)
                                end
                            end
                            
                            -- Add spacing between sibling grandchildren
                            if grandchildIdx < #childCategory.children then
                                yOffset = yOffset + SECTION_SPACING
                            end
                        end
                    end
                    
                    -- Show "all completed" message only if no achievements in child AND no grandchildren
                    if #childCategory.achievements == 0 and #childCategory.children == 0 then
                        local noAchievementsText = FontManager:CreateFontString(parent, "body", "OVERLAY")
                        noAchievementsText:SetPoint("TOPLEFT", GetLayout().BASE_INDENT * 2, -yOffset)
                        noAchievementsText:SetText("|cff88cc88" .. ((ns.L and ns.L["COMPLETED_ALL_ACHIEVEMENTS"]) or "[COMPLETED] You already completed all achievements in this category!") .. "|r")
                        yOffset = yOffset + 25
                    end
                end
                
                -- Add spacing between sibling children
                if childIdx < #rootCategory.children then
                    yOffset = yOffset + SECTION_SPACING
                end
                end  -- if childAchievementCount > 0
            end
            
            -- Show "all completed" message only if root has no achievements AND no children
            if #rootCategory.achievements == 0 and #rootCategory.children == 0 then
                local noAchievementsText = FontManager:CreateFontString(parent, "body", "OVERLAY")
                noAchievementsText:SetPoint("TOPLEFT", GetLayout().BASE_INDENT, -yOffset)
                noAchievementsText:SetText("|cff88cc88" .. ((ns.L and ns.L["COMPLETED_ALL_ACHIEVEMENTS"]) or "[COMPLETED] You already completed all achievements in this category!") .. "|r")
                yOffset = yOffset + 25
            end
        end
        
        -- Spacing after root category (standard section spacing)
        yOffset = yOffset + SECTION_SPACING
        end  -- if totalAchievements > 0
        end  -- if rootCategory
    end
    
    -- Update SearchStateManager with result count
    local searchId = "plans_achievement"
    SearchStateManager:UpdateResults(searchId, #results)
    
    return yOffset
end

-- ============================================================================
-- BROWSER RESULTS RENDERING (Separated for search refresh)
-- ============================================================================

-- Phase 4.4: Performance limit for browse results rendering
local MAX_BROWSE_RESULTS = 100

function WarbandNexus:DrawBrowserResults(parent, yOffset, width, category, searchText)
    
    -- CRITICAL: Clear all old children from parent to prevent overlap
    -- This prevents progress text from stacking on top of each other
    if parent.ClearAllPoints then
        local children = { parent:GetChildren() }
        for _, child in ipairs(children) do
            if child and child.Hide then
                child:Hide()
            end
        end
    end
    
    -- Initialize category state if needed
    if not ns.PlansLoadingState[category] then
        ns.PlansLoadingState[category] = { isLoading = false, loader = nil }
    end
    
    local categoryState = ns.PlansLoadingState[category]
    
    -- UNIFIED LOADING STATE: Core init (EnsureCollectionData) veya kategori scan
    local collLoading = ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading
    local categoryLoading = categoryState.isLoading
    if collLoading or categoryLoading then
        local state = collLoading and ns.CollectionLoadingState or categoryState
        local loadingStateData = {
            isLoading = true,
            loadingProgress = (state and state.loadingProgress) or 0,
            currentStage = (state and state.currentStage) or ((ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."),
        }
        
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            -- Use localized category name for display
            local categoryNameMap = {
                mount = (ns.L and ns.L["CATEGORY_MOUNTS"]) or "Mounts",
                pet = (ns.L and ns.L["CATEGORY_PETS"]) or "Pets",
                toy = (ns.L and ns.L["CATEGORY_TOYS"]) or "Toys",
                achievement = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements",
                illusion = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions",
                title = (ns.L and ns.L["CATEGORY_TITLES"]) or "Titles",
                transmog = (ns.L and ns.L["CATEGORY_TRANSMOG"]) or "Transmog",
            }
            local displayName = categoryNameMap[category] or (category:gsub("^%l", string.upper) .. "s")
            
            local newYOffset = UI_CreateLoadingStateCard(
                parent, 
                yOffset, 
                loadingStateData, 
                string.format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName)
            )
            return newYOffset
        else
            DebugPrint("|cffff0000[WN PlansUI]|r UI_CreateLoadingStateCard not found!")
            return yOffset + 120
        end
    end
    
    -- Get results based on category (GetUncollected* may trigger scan and set loading state)
    local results = {}
    if category == "mount" then
        results = WarbandNexus:GetUncollectedMounts(searchText, 50)
        DebugPrint("|cff9370DB[WN PlansUI]|r DrawBrowserResults: Got " .. #results .. " mounts")
    elseif category == "pet" then
        results = WarbandNexus:GetUncollectedPets(searchText, 50)
        DebugPrint("|cff9370DB[WN PlansUI]|r DrawBrowserResults: Got " .. #results .. " pets")
    elseif category == "toy" then
        results = WarbandNexus:GetUncollectedToys(searchText, 50)
        DebugPrint("|cff9370DB[WN PlansUI]|r DrawBrowserResults: Got " .. #results .. " toys")
    end

    -- Re-check loading: Core init (EnsureCollectionData) veya store boşken tetiklenen scan
    if categoryState.isLoading or (ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading) then
        local loadingStateData = {
            isLoading = true,
            loadingProgress = categoryState.loadingProgress or 0,
            currentStage = categoryState.currentStage or ((ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."),
        }
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local categoryNameMap = {
                mount = (ns.L and ns.L["CATEGORY_MOUNTS"]) or "Mounts",
                pet = (ns.L and ns.L["CATEGORY_PETS"]) or "Pets",
                toy = (ns.L and ns.L["CATEGORY_TOYS"]) or "Toys",
                achievement = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements",
                illusion = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions",
                title = (ns.L and ns.L["CATEGORY_TITLES"]) or "Titles",
                transmog = (ns.L and ns.L["CATEGORY_TRANSMOG"]) or "Transmog",
            }
            local displayName = categoryNameMap[category] or (category:gsub("^%l", string.upper) .. "s")
            local newYOffset = UI_CreateLoadingStateCard(
                parent, yOffset, loadingStateData,
                string.format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName)
            )
            return newYOffset
        end
    end

    if category == "transmog" then
        -- Transmog browser with sub-categories
        return self:DrawTransmogBrowser(parent, yOffset, width)
    elseif category == "illusion" then
        results = WarbandNexus:GetUncollectedIllusions(searchText, 50)
    elseif category == "title" then
        results = WarbandNexus:GetUncollectedTitles(searchText, 50)
    elseif category == "achievement" then
        if showCompleted then
            results = WarbandNexus.GetCompletedAchievements and WarbandNexus:GetCompletedAchievements(searchText, 99999) or {}
        else
            results = WarbandNexus:GetUncollectedAchievements(searchText, 99999)
        end

        -- Re-check loading: GetUncollected/CompletedAchievements may have triggered scan (store empty)
        if categoryState.isLoading then
            local loadingStateData = {
                isLoading = true,
                loadingProgress = categoryState.loadingProgress or 0,
                currentStage = categoryState.currentStage or ((ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."),
            }
            local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
            if UI_CreateLoadingStateCard then
                local displayName = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements"
                return UI_CreateLoadingStateCard(parent, yOffset, loadingStateData,
                    string.format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName))
            end
        end
        
        -- Update isPlanned flags for achievements
        for _, item in ipairs(results) do
            item.isPlanned = self:IsAchievementPlanned(item.id)
        end
        
        -- Filter to only planned achievements when showPlanned is active
        if showPlanned then
            local plannedOnly = {}
            for _, item in ipairs(results) do
                if item.isPlanned then
                    table.insert(plannedOnly, item)
                end
            end
            results = plannedOnly
        end
        
        -- Use table-based view for achievements (pass searchText)
        local achievementHeight = self:DrawAchievementsTable(parent, results, yOffset, width, searchText)
        -- Set container height to actual content height
        if parent and parent.SetHeight then
            parent:SetHeight(math.max(achievementHeight, 1))
        end
        return achievementHeight
    elseif category == "recipe" then
        -- Recipes require profession window to be open - show message
        local helpCard = CreateCard(parent, 80)
        helpCard:SetPoint("TOPLEFT", 0, -yOffset)
        helpCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local helpText = FontManager:CreateFontString(helpCard, "body", "OVERLAY")
        helpText:SetPoint("CENTER", 0, 10)
        helpText:SetText("|cffffcc00" .. ((ns.L and ns.L["RECIPE_BROWSER"]) or "Recipe Browser") .. "|r")
        
        local helpDesc = FontManager:CreateFontString(helpCard, "small", "OVERLAY")
        helpDesc:SetPoint("TOP", helpText, "BOTTOM", 0, -8)
        helpDesc:SetText("|cffffffff" .. ((ns.L and ns.L["RECIPE_BROWSER_DESC"]) or "Open your Profession window in-game to browse recipes.\nThe addon will scan available recipes when the window is open.") .. "|r")
        helpDesc:SetJustifyH("CENTER")
        helpDesc:SetWidth(width - 40)
        
        helpCard:Show()
        
        return yOffset + 100
    end

    -- Re-check loading for illusion/title: GetUncollected* may have triggered scan (store empty)
    if (category == "illusion" or category == "title") and categoryState.isLoading then
        local loadingStateData = {
            isLoading = true,
            loadingProgress = categoryState.loadingProgress or 0,
            currentStage = categoryState.currentStage or ((ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."),
        }
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local categoryNameMap = {
                illusion = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions",
                title = (ns.L and ns.L["CATEGORY_TITLES"]) or "Titles",
            }
            local displayName = categoryNameMap[category] or (category:gsub("^%l", string.upper) .. "s")
            return UI_CreateLoadingStateCard(parent, yOffset, loadingStateData,
                string.format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName))
        end
    end
    
    -- IMPORTANT: Refresh isPlanned flags for all results (plan cache was updated)
    for _, item in ipairs(results) do
        if category == "mount" then
            -- Mount: id field contains mountID
            item.isPlanned = self:IsMountPlanned(item.id)
        elseif category == "pet" then
            -- Pet: id field contains speciesID
            item.isPlanned = self:IsPetPlanned(item.id)
        elseif category == "toy" then
            -- Toy: id field contains itemID
            item.isPlanned = self:IsItemPlanned(PLAN_TYPES.TOY, item.id)
        elseif category == "achievement" then
            -- Achievement: id field contains achievementID
            item.isPlanned = self:IsAchievementPlanned(item.id)
        elseif category == "illusion" then
            -- Illusion: id field contains sourceID
            item.isPlanned = self:IsIllusionPlanned(item.id)
        elseif category == "title" then
            -- Title: id field contains titleID
            item.isPlanned = self:IsTitlePlanned(item.id)
        end
    end
    
    -- Show "No results" message if empty
    if #results == 0 then
        DebugPrint("|cffffcc00[WN PlansUI WARNING]|r No results to display for category: " .. category)
        
        local noResultsCard = CreateCard(parent, 80)
        noResultsCard:SetPoint("TOPLEFT", 0, -yOffset)
        noResultsCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local noResultsText = FontManager:CreateFontString(noResultsCard, "title", "OVERLAY")
        noResultsText:SetPoint("CENTER", 0, 10)
        noResultsText:SetTextColor(1, 1, 1)  -- White
        noResultsText:SetText((ns.L and ns.L["NO_FOUND_FORMAT"] and string.format(ns.L["NO_FOUND_FORMAT"], category)) or ("No " .. category .. "s found"))
        
        local noResultsDesc = FontManager:CreateFontString(noResultsCard, "body", "OVERLAY")
        noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
        noResultsDesc:SetTextColor(1, 1, 1)  -- White
        noResultsDesc:SetText((ns.L and ns.L["TRY_ADJUSTING_SEARCH"]) or "Try adjusting your search or filters.")
        
        noResultsCard:Show()
        
        return yOffset + 100
    end
    
    -- Sort results: Affordable first, then buyable, then others
    -- Sort alphabetically by name
    table.sort(results, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    
    -- Filter based on showCompleted flag (read from DB so toggle applies)
    local showCompletedBrowse = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.plansShowCompleted or false
    if showCompletedBrowse then
        -- Show ONLY collected items
        local collectedResults = {}
        for _, item in ipairs(results) do
            if item.isCollected then
                table.insert(collectedResults, item)
            end
        end
        results = collectedResults
        
        -- If no collected items, show message
        if #results == 0 then
            local noResultsCard = CreateCard(parent, 80)
            noResultsCard:SetPoint("TOPLEFT", 0, -yOffset)
            noResultsCard:SetPoint("TOPRIGHT", -10, -yOffset)
            
            local noResultsText = FontManager:CreateFontString(noResultsCard, "title", "OVERLAY")
            noResultsText:SetPoint("CENTER", 0, 10)
            noResultsText:SetTextColor(0.3, 1, 0.3)
            noResultsText:SetText((ns.L and ns.L["NO_COLLECTED_YET"] and string.format(ns.L["NO_COLLECTED_YET"], category)) or ("No collected " .. category .. "s yet"))
            
            local noResultsDesc = FontManager:CreateFontString(noResultsCard, "body", "OVERLAY")
            noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
            noResultsDesc:SetTextColor(1, 1, 1)  -- White
            noResultsDesc:SetText((ns.L and ns.L["START_COLLECTING"]) or "Start collecting to see them here!")
            
            noResultsCard:Show()
            
            return yOffset + 100
        end
    else
        -- Show ONLY uncollected items when Show Completed is off (default)
        local uncollectedResults = {}
        for _, item in ipairs(results) do
            if not item.isCollected then
                table.insert(uncollectedResults, item)
            end
        end
        results = uncollectedResults
        
        -- If no uncollected items, show message
        if #results == 0 then
            local noResultsCard = CreateCard(parent, 80)
            noResultsCard:SetPoint("TOPLEFT", 0, -yOffset)
            noResultsCard:SetPoint("TOPRIGHT", -10, -yOffset)
            
            local noResultsText = FontManager:CreateFontString(noResultsCard, "title", "OVERLAY")
            noResultsText:SetPoint("CENTER", 0, 10)
            noResultsText:SetTextColor(0.3, 1, 0.3)
            noResultsText:SetText((ns.L and ns.L["ALL_COLLECTED_CATEGORY"] and string.format(ns.L["ALL_COLLECTED_CATEGORY"], category)) or ("All " .. category .. "s collected!"))
            
            local noResultsDesc = FontManager:CreateFontString(noResultsCard, "body", "OVERLAY")
            noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
            noResultsDesc:SetTextColor(1, 1, 1)  -- White
            noResultsDesc:SetText((ns.L and ns.L["COLLECTED_EVERYTHING"]) or "You've collected everything in this category!")
            
            noResultsCard:Show()
            
            return yOffset + 100
        end
    end
    
    -- Filter based on showPlanned flag (applied after showCompleted filter)
    if showPlanned then
        local plannedResults = {}
        for _, item in ipairs(results) do
            if item.isPlanned then
                table.insert(plannedResults, item)
            end
        end
        results = plannedResults
        
        if #results == 0 then
            local noResultsCard = CreateCard(parent, 80)
            noResultsCard:SetPoint("TOPLEFT", 0, -yOffset)
            noResultsCard:SetPoint("TOPRIGHT", -10, -yOffset)
            
            local noResultsText = FontManager:CreateFontString(noResultsCard, "title", "OVERLAY")
            noResultsText:SetPoint("CENTER", 0, 10)
            noResultsText:SetTextColor(1, 0.8, 0)
            noResultsText:SetText((ns.L and ns.L["NO_PLANNED_ITEMS"] and string.format(ns.L["NO_PLANNED_ITEMS"], category)) or ("No planned " .. category .. "s yet"))
            
            local noResultsDesc = FontManager:CreateFontString(noResultsCard, "body", "OVERLAY")
            noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
            noResultsDesc:SetTextColor(1, 1, 1)
            noResultsDesc:SetText((ns.L and ns.L["ADD_ITEMS_TO_PLANS"]) or "Add items to your plans to see them here!")
            
            noResultsCard:Show()
            
            return yOffset + 100
        end
    end
    
    -- Phase 4.4: Limit browse results rendering for performance
    local totalResults = #results
    local resultsToRender = math.min(totalResults, MAX_BROWSE_RESULTS)
    
    -- === 2-COLUMN CARD GRID (Fixed height, clean layout) ===
    local cardSpacing = 8
    local cardWidth = (width - cardSpacing) / 2  -- 2 columns with spacing to match title bar width
    local cardHeight = 105  -- Compact card height
    local col = 0
    
    -- Show truncation message if results were limited
    if totalResults > MAX_BROWSE_RESULTS then
        local truncationMsg = FontManager:CreateFontString(parent, "body", "OVERLAY")
        truncationMsg:SetPoint("TOPLEFT", 0, -yOffset)
        truncationMsg:SetPoint("TOPRIGHT", -10, -yOffset)
        truncationMsg:SetJustifyH("CENTER")
        local showingFormat = (ns.L and ns.L["SHOWING_X_OF_Y"]) or "Showing %d of %d results"
        truncationMsg:SetText("|cff888888" .. string.format(showingFormat, MAX_BROWSE_RESULTS, totalResults) .. "|r")
        yOffset = yOffset + 24
    end
    
    for i = 1, resultsToRender do
        local item = results[i]
        item.category = category
        -- Resolve empty source from API so browser shows same source as collection tabs (e.g. Voidstorm Fishing).
        if (not item.source or item.source == "") and item.id then
            if category == "mount" and C_MountJournal and C_MountJournal.GetMountInfoExtraByID then
                local ok, _, _, src = pcall(C_MountJournal.GetMountInfoExtraByID, item.id)
                if ok and src and type(src) == "string" and src ~= "" and (not issecretvalue or not issecretvalue(src)) then
                    item.source = src
                end
            elseif category == "pet" and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
                local ok, _, _, _, _, src = pcall(C_PetJournal.GetPetInfoBySpeciesID, item.id)
                if ok and src and type(src) == "string" and src ~= "" and (not issecretvalue or not issecretvalue(src)) then
                    item.source = src
                end
            end
        end
        -- Parse source for display
        local sources = self:ParseMultipleSources(item.source)
        local firstSource = sources[1] or {}
        
        -- Calculate position
        local xOffset = col * (cardWidth + cardSpacing)
        
        local card = CreateCard(parent, cardHeight)
        card:SetWidth(cardWidth)
        card:SetPoint("TOPLEFT", xOffset, -yOffset)
        card:EnableMouse(true)
        
        -- Apply color-coded border based on status
        if ApplyVisuals then
            local borderColor
            if item.isCollected or item.isPlanned then
                -- Added/Collected: Green border
                borderColor = {0.30, 0.90, 0.30, 0.8}
            else
                -- Not planned: Default accent border
                borderColor = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
            end
            ApplyVisuals(card, {0.08, 0.08, 0.10, 1}, borderColor)
        end
        
        -- === ICON (46x46, top-left) ===
        local iconBorder = ns.UI.Factory:CreateContainer(card, 46, 46)
        iconBorder:SetPoint("TOPLEFT", 10, -10)
        iconBorder:EnableMouse(false)
        
        -- Create icon texture or atlas
        local iconTexture = item.iconAtlas or item.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        local iconIsAtlas = (item.iconAtlas ~= nil)
        
        local iconFrameObj = CreateIcon(card, iconTexture, 42, iconIsAtlas, nil, false)
        if iconFrameObj then
            iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
            iconFrameObj:EnableMouse(false)
            iconFrameObj:Show()  -- CRITICAL: Show the icon!
        end
        
        -- NO hover effect on plan cards (as requested)
        
        -- === TITLE ===
        local nameText = FontManager:CreateFontString(card, "body", "OVERLAY")
        nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
        nameText:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        local displayName = FormatTextNumbers(item.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"))
        if item.isPlanned then
            local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
            displayName = displayName .. " |cffffcc00(" .. plannedWord .. ")|r"
        end
        nameText:SetText("|cffffffff" .. displayName .. "|r")
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(true)
        nameText:SetMaxLines(2)
        nameText:SetNonSpaceWrap(false)
        
        -- === POINTS / TYPE BADGE (directly under title, NO spacing) ===
        if category == "achievement" and item.points then
            -- Achievement: Show shield icon + points (like in My Plans)
            local shieldFrame = ns.UI.Factory:CreateContainer(card, 20, 20)
            shieldFrame:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, 0)
            shieldFrame:EnableMouse(false)  -- Allow clicks to pass through
            
            local shieldIcon = shieldFrame:CreateTexture(nil, "OVERLAY")
            shieldIcon:SetAllPoints()
            local shieldSuccess = pcall(function()
                shieldIcon:SetAtlas("UI-Achievement-Shield-NoPoints", false)
            end)
            if not shieldSuccess then
                shieldFrame:Hide()
            else
                shieldIcon:SetSnapToPixelGrid(false)
                shieldIcon:SetTexelSnappingBias(0)
                shieldFrame:Show()  -- CRITICAL: Show the shield icon!
            end
            
            local pointsText = FontManager:CreateFontString(card, "body", "OVERLAY")
            pointsText:SetPoint("LEFT", shieldFrame, "RIGHT", 4, 0)
            pointsText:SetText(string.format("|cff%02x%02x%02x" .. ((ns.L and ns.L["POINTS_FORMAT"]) or "%d Points") .. "|r", 
                255*255, 204*255, 51*255,  -- Gold color
                item.points))
            pointsText:EnableMouse(false)  -- Allow clicks to pass through
        else
            -- Other types: Show type badge with icon (like in My Plans)
            local typeNames = {
                mount = (ns.L and ns.L["TYPE_MOUNT"]) or "Mount",
                pet = (ns.L and ns.L["TYPE_PET"]) or "Pet",
                toy = (ns.L and ns.L["TYPE_TOY"]) or "Toy",
                recipe = (ns.L and ns.L["TYPE_RECIPE"]) or "Recipe",
                illusion = (ns.L and ns.L["TYPE_ILLUSION"]) or "Illusion",
                title = (ns.L and ns.L["TYPE_TITLE"]) or "Title",
                transmog = (ns.L and ns.L["TYPE_TRANSMOG"]) or "Transmog",
            }
            local typeName = typeNames[category] or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
            
            -- Type icon atlas mapping
            local typeIcons = {
                mount = "dragon-rostrum",
                pet = "WildBattlePetCapturable",
                toy = "CreationCatalyst-32x32",
                recipe = nil,  -- No specific icon for recipes
                illusion = "UpgradeItem-32x32",
                title = "poi-legendsoftheharanir",
                transmog = "poi-transmogrifier",
            }
            local typeIconAtlas = typeIcons[category]
            
            -- Get type color from typeColors (same as My Plans)
            local typeColors = {
                mount = {0.6, 0.8, 1},
                pet = {0.5, 1, 0.5},
                toy = {1, 0.9, 0.2},
                recipe = {0.8, 0.8, 0.5},
                illusion = {0.8, 0.5, 1},
                title = {0.6, 0.6, 0.6},
                transmog = {0.8, 0.5, 1},
            }
            local typeColor = typeColors[category] or {0.6, 0.6, 0.6}
            
            -- Create icon frame (like Achievement shield icon)
            local iconFrame = nil
            if typeIconAtlas then
                iconFrame = ns.UI.Factory:CreateContainer(card, 20, 20)
                iconFrame:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, 0)
                iconFrame:EnableMouse(false)  -- Allow clicks to pass through
                
                local iconTexture = iconFrame:CreateTexture(nil, "OVERLAY")
                iconTexture:SetAllPoints()
                local iconSuccess = pcall(function()
                    iconTexture:SetAtlas(typeIconAtlas, false)
                end)
                if not iconSuccess then
                    iconFrame:Hide()
                    iconFrame = nil
                else
                    iconTexture:SetSnapToPixelGrid(false)
                    iconTexture:SetTexelSnappingBias(0)
                    iconFrame:Show()  -- CRITICAL: Show the type icon!
                end
            end
            
            -- Create type badge text
            local typeBadge = FontManager:CreateFontString(card, "body", "OVERLAY")
            if iconFrame then
                -- Position text to the right of icon (like Achievement points)
                typeBadge:SetPoint("LEFT", iconFrame, "RIGHT", 4, 0)
            else
                -- No icon, position like before
                typeBadge:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, 0)
            end
            typeBadge:SetText(string.format("|cff%02x%02x%02x%s|r", 
                typeColor[1]*255, typeColor[2]*255, typeColor[3]*255,
                typeName))
            typeBadge:EnableMouse(false)  -- Allow clicks to pass through
        end
        
        -- === LINE 3: Source Info (below icon) ===
        local line3Y = -60  -- Below icon
        
        -- TITLE-SPECIFIC: Show source achievement with clickable link
        if category == "title" and item.sourceAchievement then
            local achievementText = FontManager:CreateFontString(card, "body", "OVERLAY")
            achievementText:SetPoint("TOPLEFT", 10, line3Y)
            achievementText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
            -- Use localized strings for Source label and Achievement type
            local sourceLabel = (ns.L and ns.L["SOURCE_LABEL"]) or "Source:"
            local achievementType = (ns.L and ns.L["SOURCE_TYPE_ACHIEVEMENT"]) or (BATTLE_PET_SOURCE_6 or "Achievement")
            local sourceText = (ns.L and ns.L["SOURCE_ACHIEVEMENT_FORMAT"] and string.format(ns.L["SOURCE_ACHIEVEMENT_FORMAT"], sourceLabel, achievementType, item.sourceAchievement)) or (sourceLabel .. " |cff00ff00[" .. achievementType .. " " .. item.sourceAchievement .. "]|r")
            achievementText:SetText("|TInterface\\Icons\\Achievement_General:16:16|t " .. sourceText)
            achievementText:SetTextColor(1, 1, 1)
            achievementText:SetJustifyH("LEFT")
            achievementText:SetWordWrap(true)
            achievementText:SetMaxLines(2)
            achievementText:SetNonSpaceWrap(false)
            
            -- Make card clickable to jump to achievement
            card:EnableMouse(true)
            card:SetScript("OnMouseDown", function(self, button)
                if button == "LeftButton" then
                    -- Switch to Achievements tab
                    WarbandNexus:ShowTab("achievements")
                    
                    -- Expand to achievement and scroll to it
                    -- Store in namespace for achievement UI to pick up
                    ns.PendingAchievementHighlight = item.sourceAchievement
                    
                    DebugPrint("|cff00ff00[WN PlansUI]|r Jumping to achievement: " .. item.sourceAchievement)
                end
            end)
            
            -- Add hover effect for clickable card
            card:SetScript("OnEnter", function(self)
                if ApplyVisuals then
                    local hoverBorder = {0.3, 1.0, 0.3, 1.0}  -- Green for clickable
                    ApplyVisuals(self, {0.08, 0.08, 0.10, 1}, hoverBorder)
                end
            end)
            card:SetScript("OnLeave", function(self)
                if ApplyVisuals then
                    local defaultBorder = item.isCollected or item.isPlanned 
                        and {0.30, 0.90, 0.30, 0.8} 
                        or {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
                    ApplyVisuals(self, {0.08, 0.08, 0.10, 1}, defaultBorder)
                end
            end)
        elseif firstSource.vendor then
            local vendorText = FontManager:CreateFontString(card, "body", "OVERLAY")
            vendorText:SetPoint("TOPLEFT", 10, line3Y)
            vendorText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            vendorText:SetText("|A:Class:16:16|a " .. ((ns.L and ns.L["VENDOR_LABEL"]) or "Vendor: ") .. firstSource.vendor)
            vendorText:SetTextColor(1, 1, 1)
            vendorText:SetJustifyH("LEFT")
            vendorText:SetWordWrap(true)
            vendorText:SetMaxLines(2)
            vendorText:SetNonSpaceWrap(false)
        elseif firstSource.npc then
            local npcText = FontManager:CreateFontString(card, "body", "OVERLAY")
            npcText:SetPoint("TOPLEFT", 10, line3Y)
            npcText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            npcText:SetText("|A:Class:16:16|a " .. ((ns.L and ns.L["DROP_LABEL"]) or "Drop: ") .. firstSource.npc)
            npcText:SetTextColor(1, 1, 1)
            npcText:SetJustifyH("LEFT")
            npcText:SetWordWrap(true)
            npcText:SetMaxLines(2)
            npcText:SetNonSpaceWrap(false)
        elseif firstSource.faction then
            local factionText = FontManager:CreateFontString(card, "body", "OVERLAY")
            factionText:SetPoint("TOPLEFT", 10, line3Y)
            factionText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            local factionLabel = (ns.L and ns.L["FACTION_LABEL"]) or "Faction:"
            local displayText = "|A:Class:16:16|a " .. factionLabel .. " " .. firstSource.faction
            if firstSource.renown then
                local repType = firstSource.isFriendship and ((ns.L and ns.L["FRIENDSHIP_LABEL"]) or "Friendship") or ((ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown")
                displayText = displayText .. " |cffffcc00(" .. repType .. " " .. firstSource.renown .. ")|r"
            end
            factionText:SetText(displayText)
            factionText:SetTextColor(1, 1, 1)
            factionText:SetJustifyH("LEFT")
            factionText:SetWordWrap(true)
            factionText:SetMaxLines(2)
            factionText:SetNonSpaceWrap(false)
        end
        
        -- === LINE 4: Zone or Location ===
        if firstSource.zone then
            local zoneText = FontManager:CreateFontString(card, "body", "OVERLAY")
            -- Use line3Y if no vendor/NPC/faction above it, otherwise -76 (adjusted for bigger font)
            local zoneY = (firstSource.vendor or firstSource.npc or firstSource.faction) and -78 or line3Y
            zoneText:SetPoint("TOPLEFT", 10, zoneY)
            zoneText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            zoneText:SetText("|A:Class:16:16|a " .. ((ns.L and ns.L["ZONE_LABEL"]) or "Zone: ") .. firstSource.zone)
            zoneText:SetTextColor(1, 1, 1)
            zoneText:SetJustifyH("LEFT")
            zoneText:SetWordWrap(true)
            zoneText:SetMaxLines(1)
            zoneText:SetNonSpaceWrap(false)
        end
        
        -- === LINE 3+: Info/Progress/Reward BELOW ICON (same as mounts/pets/toys) ===
        if not firstSource.vendor and not firstSource.zone and not firstSource.npc and not firstSource.faction then
            -- Special handling for achievements
            if category == "achievement" then
                local rawText = item.source or ""
                if WarbandNexus.CleanSourceText then
                    rawText = WarbandNexus:CleanSourceText(rawText)
                end
                
                -- Extract progress if it exists
                local description, progress = rawText:match("^(.-)%s*(Progress:%s*.+)$")
                
                local lastElement = nil
                
                -- === INFORMATION (Description) - BELOW icon, WHITE color ===
                if description and description ~= "" then
                    local infoText = FontManager:CreateFontString(card, "body", "OVERLAY")
                    infoText:SetPoint("TOPLEFT", 10, line3Y)
                    infoText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    infoText:SetText("|cff88ff88" .. ((ns.L and ns.L["INFORMATION_LABEL"]) or "Information:") .. "|r |cffffffff" .. description .. "|r")
                    infoText:SetJustifyH("LEFT")
                    infoText:SetWordWrap(true)
                    infoText:SetMaxLines(2)
                    infoText:SetNonSpaceWrap(false)
                    lastElement = infoText
                elseif item.description and item.description ~= "" then
                    local infoText = FontManager:CreateFontString(card, "body", "OVERLAY")
                    infoText:SetPoint("TOPLEFT", 10, line3Y)
                    infoText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    infoText:SetText("|cff88ff88" .. ((ns.L and ns.L["INFORMATION_LABEL"]) or "Information:") .. "|r |cffffffff" .. FormatTextNumbers(item.description) .. "|r")
                    infoText:SetJustifyH("LEFT")
                    infoText:SetWordWrap(true)
                    infoText:SetMaxLines(2)
                    infoText:SetNonSpaceWrap(false)
                    lastElement = infoText
                end
                
                -- === PROGRESS - BELOW information, NO spacing ===
                if progress then
                    local progressText = FontManager:CreateFontString(card, "body", "OVERLAY")
                    if lastElement then
                        progressText:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, -2)
                    else
                        progressText:SetPoint("TOPLEFT", 10, line3Y)
                    end
                    progressText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    local progressLabel = (ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:"
                    local cleanProgress = progress:gsub(progressLabel:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "%s*", "")
                    progressText:SetText("|cffffcc00" .. progressLabel .. "|r |cffffffff" .. cleanProgress .. "|r")
                    progressText:SetJustifyH("LEFT")
                    progressText:SetWordWrap(false)
                    lastElement = progressText
                end
                
                -- === REWARD - BELOW progress WITH spacing (one line gap) ===
                if item.rewardText and item.rewardText ~= "" then
                    local rewardText = FontManager:CreateFontString(card, "body", "OVERLAY")
                    if lastElement then
                        rewardText:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, -14)  -- 14px spacing
                    else
                        rewardText:SetPoint("TOPLEFT", 10, line3Y)
                    end
                    rewardText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    rewardText:SetText("|cff88ff88" .. ((ns.L and ns.L["REWARD_LABEL"]) or "Reward:") .. "|r |cffffffff" .. item.rewardText .. "|r")
                    rewardText:SetJustifyH("LEFT")
                    rewardText:SetWordWrap(true)
                    rewardText:SetMaxLines(2)
                    rewardText:SetNonSpaceWrap(false)
                end
            else
                -- Regular source text handling for mounts/pets/toys/illusions
                -- Skip source display for titles (they just show the title name)
                if category ~= "title" then
                    -- Use PlanCardFactory to create source text (centralized)
                    local PlanCardFactory = ns.UI_PlanCardFactory
                    if PlanCardFactory and PlanCardFactory.CreateSourceText then
                        local sourceElement = PlanCardFactory:CreateSourceText(card, item, line3Y)
                        -- sourceElement is used for layout, but we don't need to track it here
                    else
                        -- Fallback if factory not available
                        local sourceText = FontManager:CreateFontString(card, "body", "OVERLAY")
                        sourceText:SetPoint("TOPLEFT", 10, line3Y)
                        sourceText:SetPoint("RIGHT", card, "RIGHT", -80, 0)
                        sourceText:SetText("|A:Class:16:16|a |cff99ccff" .. ((ns.L and ns.L["SOURCE_LABEL"]) or "Source:") .. "|r |cffffffff" .. (item.source or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")) .. "|r")
                        sourceText:SetJustifyH("LEFT")
                        sourceText:SetWordWrap(true)
                        sourceText:SetMaxLines(2)
                    end
                end
            end
        end
        
        -- Add/Added button (bottom right) using Factory
        local PlanCardFactory = ns.UI_PlanCardFactory
        
        if item.isPlanned then
            PlanCardFactory.CreateAddedIndicator(card, {
                buttonType = "card",
                label = (ns.L and ns.L["ADDED"]) or "Added",
                fontCategory = "body"
            })
        else
            local addBtn = PlanCardFactory.CreateAddButton(card, {
                buttonType = "card",
                onClick = function(self)
                    local planData = {
                        -- itemID: for toys (id field), or fallback to item.itemID
                        itemID = (category == "toy") and item.id or item.itemID,
                        name = item.name,
                        icon = item.icon,
                        source = item.source,
                        -- Mount uses 'id' field (contains mountID)
                        mountID = (category == "mount") and item.id or nil,
                        -- Pet uses 'id' field (contains speciesID)
                        speciesID = (category == "pet") and item.id or nil,
                        -- Achievement uses 'id' field (contains achievementID)
                        achievementID = (category == "achievement") and item.id or nil,
                        -- Illusion uses 'id' field (contains sourceID)
                        illusionID = (category == "illusion") and item.id or nil,
                        -- Title uses 'id' field (contains titleID)
                        titleID = (category == "title") and item.id or nil,
                        rewardText = item.rewardText,
                    }
                    
                    -- Add type to planData
                    planData.type = category
                    
                    WarbandNexus:AddPlan(planData)
                    
                    -- Update card border to accent immediately (added state)
                    if UpdateBorderColor and COLORS and COLORS.accent then
                        UpdateBorderColor(card, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
                    end
                    
                    -- Hide the Add button and show Added indicator (self is the button)
                    self:Hide()
                    PlanCardFactory.CreateAddedIndicator(card, {
                        buttonType = "card",
                        label = (ns.L and ns.L["ADDED"]) or "Added",
                        fontCategory = "body"
                    })
                end
            })
        end
        
        -- Try count badge: only for drop-source collectibles (rare, container, fishing, etc.), not vendor/achievement/guaranteed.
        local browserTryTypes = { mount = true, pet = true, toy = true, illusion = true }
        if browserTryTypes[category] and item.id and WarbandNexus and WarbandNexus.GetTryCount then
            local count = WarbandNexus:GetTryCount(category, item.id)
            if count == nil then count = 0 end
            local isDrop = WarbandNexus.IsDropSourceCollectible and WarbandNexus:IsDropSourceCollectible(category, item.id)
            local isGuaranteed = WarbandNexus.IsGuaranteedCollectible and WarbandNexus:IsGuaranteedCollectible(category, item.id)
            if (isDrop and not isGuaranteed) or count > 0 then
                local triesLabel = (ns.L and ns.L["TRIES"]) or "Tries"
                local tryText = FontManager:CreateFontString(card, "body", "OVERLAY")
                tryText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10)
                tryText:SetText("|cffaaddff" .. triesLabel .. ":|r |cffffffff" .. tostring(count) .. "|r")
                tryText:SetJustifyH("RIGHT")
                tryText:SetWordWrap(false)
            end
        end
        
        -- CRITICAL: Show the card!
        card:Show()
        
        -- Move to next position
        col = col + 1
        if col >= 2 then
            col = 0
            yOffset = yOffset + cardHeight + cardSpacing
        end
    end
    
    -- Handle odd number of items
    if col > 0 then
        yOffset = yOffset + cardHeight + cardSpacing
    end
    
    if #results == 0 then
        -- Create unique search ID for this category
        local searchId = "plans_" .. (category or "unknown"):lower()
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, searchText, searchId)
        SearchStateManager:UpdateResults(searchId, 0)
        return height
    end
    
    -- Update SearchStateManager with result count
    local searchId = "plans_" .. (category or "unknown"):lower()
    SearchStateManager:UpdateResults(searchId, #results)
    
    return yOffset + 10
end

-- ============================================================================
-- CUSTOM PLAN DIALOG
-- ============================================================================

function WarbandNexus:ShowCustomPlanDialog()
    -- Disable Add Custom button to prevent multiple dialogs
    if self.addCustomBtn then
        self.addCustomBtn:Disable()
        self.addCustomBtn:SetAlpha(0.5)
    end

    
    -- Get character info
    local currentName = UnitName("player")
    local currentRealm = GetRealmName()
    local _, currentClass = UnitClass("player")
    local classColors = RAID_CLASS_COLORS[currentClass]
    
    -- Create external window using helper
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "CustomPlanDialog",
        title = (ns.L and ns.L["CREATE_CUSTOM_PLAN"]) or "Create Custom Plan",
        icon = "Bonus-Objective-Star",  -- Use atlas for custom plans
        iconIsAtlas = true,
        width = 450,
        height = 480,  -- Height for title + description + reset cycle + duration
        onClose = function()
            -- Re-enable Add Custom button
            if WarbandNexus.addCustomBtn then
                WarbandNexus.addCustomBtn:Enable()
                WarbandNexus.addCustomBtn:SetAlpha(1)
            end
        end
    })
    
    -- If dialog creation failed (duplicate), return
    if not dialog then
        if self.addCustomBtn then
            self.addCustomBtn:Enable()
            self.addCustomBtn:SetAlpha(1)
        end
        return
    end
    
    -- Character section with icon (using Factory pattern)
    local charFrame = ns.UI.Factory:CreateContainer(contentFrame, 420, 45)
    charFrame:SetPoint("TOP", 0, -15)
    
    -- Get race-gender info
    local _, englishRace = UnitRace("player")
    local gender = UnitSex("player")
    local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
    
    -- Character race icon with border (using Factory pattern)
    local iconContainer = ns.UI.Factory:CreateContainer(charFrame, 36, 36)
    iconContainer:SetPoint("LEFT", 12, 0)
    
    -- Apply border with class color
    if ApplyVisuals then
        if classColors then
            ApplyVisuals(iconContainer, {0.08, 0.08, 0.10, 1}, {classColors.r, classColors.g, classColors.b, 1})
        else
            ApplyVisuals(iconContainer, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8})
        end
    end
    
    -- Character race icon (using atlas)
    local charIconFrame = CreateIcon(iconContainer, raceAtlas, 28, true, nil, true)
    charIconFrame:SetPoint("CENTER", 0, 0)
    charIconFrame:Show()
    
    -- Character name with class color (larger font)
    local charText = FontManager:CreateFontString(charFrame, "title", "OVERLAY")
    charText:SetPoint("LEFT", iconContainer, "RIGHT", 10, 0)
    if classColors then
        charText:SetTextColor(classColors.r, classColors.g, classColors.b)
    else
        charText:SetTextColor(1, 0.8, 0)
    end
    charText:SetText(currentName .. "-" .. currentRealm)
    
    -- Title label
    local titleLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    titleLabel:SetPoint("TOPLEFT", 12, -75)
    titleLabel:SetText("|cff" .. string.format("%02x%02x%02x", COLORS.accent[1]*255, COLORS.accent[2]*255, COLORS.accent[3]*255) .. ((ns.L and ns.L["TITLE_LABEL"]) or "Title:") .. "|r")
    
    -- Title input container (using Factory pattern)
    local titleInputBg = ns.UI.Factory:CreateContainer(contentFrame, 410, 35)
    titleInputBg:SetPoint("TOPLEFT", 12, -97)
    
    -- Apply border to input
    if ApplyVisuals then
        ApplyVisuals(titleInputBg, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    local titleInput = ns.UI.Factory:CreateEditBox(titleInputBg)
    titleInput:SetSize(395, 30)
    titleInput:SetPoint("LEFT", 8, 0)
    titleInput:SetFontObject(ChatFontNormal)
    titleInput:SetTextColor(1, 1, 1, 1)
    titleInput:SetAutoFocus(false)
    titleInput:SetMaxLetters(32)  -- Max 32 characters
    titleInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    titleInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- Prevent Enter key from creating new lines
    titleInput:SetScript("OnChar", function(self, char)
        if char == "\n" or char == "\r" then
            local text = self:GetText()
            self:SetText(text:gsub("[\n\r]", ""))
        end
    end)
    
    -- Make container clickable to focus EditBox
    titleInputBg:EnableMouse(true)
    titleInputBg:SetScript("OnMouseDown", function()
        titleInput:SetFocus()
    end)
    
    -- Description label
    local descLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    descLabel:SetPoint("TOPLEFT", 12, -145)
    descLabel:SetText("|cff" .. string.format("%02x%02x%02x", COLORS.accent[1]*255, COLORS.accent[2]*255, COLORS.accent[3]*255) .. ((ns.L and ns.L["DESCRIPTION_LABEL"]) or "Description:") .. "|r")
    
    -- Description input container (scrollable, single line) (using Factory pattern)
    local descInputBg = ns.UI.Factory:CreateContainer(contentFrame, 410, 35)  -- Reduced height for single line
    descInputBg:SetPoint("TOPLEFT", 12, -167)
    
    -- Apply border to input
    if ApplyVisuals then
        ApplyVisuals(descInputBg, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    local descInput = ns.UI.Factory:CreateEditBox(descInputBg)
    descInput:SetSize(395, 30)
    descInput:SetPoint("LEFT", 8, 0)
    descInput:SetFontObject(ChatFontNormal)
    descInput:SetTextColor(1, 1, 1, 1)
    descInput:SetAutoFocus(false)
    descInput:SetMultiLine(false)  -- Single line only - prevents Enter from creating new lines
    descInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    descInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    -- Limit to 300 characters total, max 30 characters per word
    descInput:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        -- Remove any newlines that might have been inserted
        text = text:gsub("[\n\r]", " ")
        
        -- Enforce word length limit (max 30 chars per word)
        local maxWordLength = 30
        local words = {}
        local modified = false
        
        for word in text:gmatch("%S+") do  -- Split by whitespace
            if string.len(word) > maxWordLength then
                -- Truncate long word
                word = string.sub(word, 1, maxWordLength)
                modified = true
            end
            table.insert(words, word)
        end
        
        -- Reconstruct text with single spaces
        if modified then
            text = table.concat(words, " ")
        end
        
        -- Enforce 300 character limit
        local maxChars = 300
        if string.len(text) > maxChars then
            text = string.sub(text, 1, maxChars)
            modified = true
        end
        
        -- Update text if modified
        if modified and text ~= self:GetText() then
            local cursorPos = self:GetCursorPosition()
            self:SetText(text)
            self:SetCursorPosition(math.min(cursorPos, string.len(text)))
        end
    end)
    
    -- Prevent Enter key from creating new lines
    descInput:SetScript("OnChar", function(self, char)
        if char == "\n" or char == "\r" then
            local text = self:GetText()
            local cursorPos = self:GetCursorPosition()
            self:SetText(text:gsub("[\n\r]", " "))
            self:SetCursorPosition(cursorPos)
        end
    end)
    
    -- Make container clickable to focus EditBox
    descInputBg:EnableMouse(true)
    descInputBg:SetScript("OnMouseDown", function()
        descInput:SetFocus()
    end)
    
    -- Reset Cycle selection
    local resetLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    resetLabel:SetPoint("TOPLEFT", 12, -215)
    resetLabel:SetText("|cff" .. string.format("%02x%02x%02x", COLORS.accent[1]*255, COLORS.accent[2]*255, COLORS.accent[3]*255) .. ((ns.L and ns.L["RESET_CYCLE_LABEL"]) or "Reset Cycle:") .. "|r")
    
    -- Reset cycle toggle state
    local selectedResetType = "none"
    local selectedCycleCount = 7  -- Default cycle count
    
    -- Toggle button factory
    local function CreateResetToggle(parent, label, value, xOffset)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(120, 28)
        btn:SetPoint("TOPLEFT", xOffset, -237)
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        btn:SetBackdropColor(0.08, 0.08, 0.10, 1)
        btn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
        
        local text = FontManager:CreateFontString(btn, "body", "OVERLAY")
        text:SetPoint("CENTER")
        text:SetText(label)
        text:SetTextColor(0.7, 0.7, 0.7)
        btn.label = text
        btn.value = value
        
        return btn
    end
    
    local resetBtnNone = CreateResetToggle(contentFrame, (ns.L and ns.L["RESET_NONE"]) or "None", "none", 12)
    local resetBtnDaily = CreateResetToggle(contentFrame, (ns.L and ns.L["DAILY_RESET"]) or "Daily Reset", "daily", 142)
    local resetBtnWeekly = CreateResetToggle(contentFrame, (ns.L and ns.L["WEEKLY_RESET"]) or "Weekly Reset", "weekly", 272)
    
    local resetButtons = { resetBtnNone, resetBtnDaily, resetBtnWeekly }
    
    -- Duration row (hidden by default, shown when Daily/Weekly selected)
    local durationRow = CreateFrame("Frame", nil, contentFrame)
    durationRow:SetSize(420, 30)
    durationRow:SetPoint("TOPLEFT", 12, -275)
    durationRow:Hide()
    
    local durationLabel = FontManager:CreateFontString(durationRow, "body", "OVERLAY")
    durationLabel:SetPoint("LEFT", 0, 0)
    durationLabel:SetTextColor(0.7, 0.7, 0.7)
    
    -- Minus button
    local minusBtn = CreateFrame("Button", nil, durationRow, "BackdropTemplate")
    minusBtn:SetSize(28, 28)
    minusBtn:SetPoint("LEFT", 160, 0)
    minusBtn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    minusBtn:SetBackdropColor(0.12, 0.12, 0.14, 1)
    minusBtn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
    local minusText = FontManager:CreateFontString(minusBtn, "title", "OVERLAY")
    minusText:SetPoint("CENTER", 0, 1)
    minusText:SetText("-")
    minusText:SetTextColor(1, 1, 1)
    
    -- Count display
    local countDisplay = FontManager:CreateFontString(durationRow, "title", "OVERLAY")
    countDisplay:SetPoint("LEFT", minusBtn, "RIGHT", 12, 0)
    countDisplay:SetTextColor(1, 1, 1)
    countDisplay:SetWidth(30)
    countDisplay:SetJustifyH("CENTER")
    
    -- Plus button
    local plusBtn = CreateFrame("Button", nil, durationRow, "BackdropTemplate")
    plusBtn:SetSize(28, 28)
    plusBtn:SetPoint("LEFT", countDisplay, "RIGHT", 12, 0)
    plusBtn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    plusBtn:SetBackdropColor(0.12, 0.12, 0.14, 1)
    plusBtn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
    local plusText = FontManager:CreateFontString(plusBtn, "title", "OVERLAY")
    plusText:SetPoint("CENTER", 0, 1)
    plusText:SetText("+")
    plusText:SetTextColor(1, 1, 1)
    
    -- Update duration display
    local function UpdateDurationDisplay()
        countDisplay:SetText(tostring(selectedCycleCount))
        durationLabel:SetText(((ns.L and ns.L["DURATION_LABEL"]) or "Duration") .. ":  ")
    end
    
    -- Unit label after count
    local unitLabel = FontManager:CreateFontString(durationRow, "body", "OVERLAY")
    unitLabel:SetPoint("LEFT", plusBtn, "RIGHT", 10, 0)
    unitLabel:SetTextColor(0.7, 0.7, 0.7)
    
    local function UpdateUnitLabel()
        if selectedResetType == "daily" then
            unitLabel:SetText((ns.L and ns.L["DAYS_LABEL"]) or "days")
        elseif selectedResetType == "weekly" then
            unitLabel:SetText((ns.L and ns.L["WEEKS_LABEL"]) or "weeks")
        end
    end
    
    minusBtn:SetScript("OnClick", function()
        if selectedCycleCount > 1 then
            selectedCycleCount = selectedCycleCount - 1
            UpdateDurationDisplay()
        end
    end)
    minusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
    end)
    minusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
    end)
    
    plusBtn:SetScript("OnClick", function()
        if selectedCycleCount < 99 then
            selectedCycleCount = selectedCycleCount + 1
            UpdateDurationDisplay()
        end
    end)
    plusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
    end)
    plusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
    end)
    
    -- Update button visuals based on selection
    local function UpdateResetButtons()
        for _, btn in ipairs(resetButtons) do
            if btn.value == selectedResetType then
                btn:SetBackdropColor(COLORS.accent[1] * 0.4, COLORS.accent[2] * 0.4, COLORS.accent[3] * 0.4, 1)
                btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
                btn.label:SetTextColor(1, 1, 1)
            else
                btn:SetBackdropColor(0.08, 0.08, 0.10, 1)
                btn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
                btn.label:SetTextColor(0.7, 0.7, 0.7)
            end
        end
        
        -- Show/hide duration row based on selection
        if selectedResetType == "none" then
            durationRow:Hide()
        else
            -- Set default cycle counts based on type
            if selectedResetType == "daily" then
                selectedCycleCount = math.max(1, math.min(selectedCycleCount, 99))
            elseif selectedResetType == "weekly" then
                selectedCycleCount = math.max(1, math.min(selectedCycleCount, 99))
            end
            UpdateDurationDisplay()
            UpdateUnitLabel()
            durationRow:Show()
        end
    end
    
    for _, btn in ipairs(resetButtons) do
        btn:SetScript("OnClick", function(self)
            selectedResetType = self.value
            -- Set sensible defaults when switching type
            if self.value == "daily" then
                selectedCycleCount = 7
            elseif self.value == "weekly" then
                selectedCycleCount = 4
            end
            UpdateResetButtons()
        end)
        btn:SetScript("OnEnter", function(self)
            if self.value ~= selectedResetType then
                self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.value ~= selectedResetType then
                self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
            end
        end)
    end
    
    -- Set initial state (None selected)
    UpdateResetButtons()
    
    -- Buttons (symmetrically centered with more spacing from inputs)
    local saveBtn = CreateThemedButton(contentFrame, (ns.L and ns.L["SAVE"]) or "Save", 100)
    saveBtn:SetPoint("BOTTOM", -55, 12)
    saveBtn:SetScript("OnClick", function()
        local title = titleInput:GetText()
        local description = descInput:GetText()
        
        if title and title ~= "" then
            local cycleCount = (selectedResetType ~= "none") and selectedCycleCount or nil
            WarbandNexus:SaveCustomPlan(title, description, selectedResetType, cycleCount)
            dialog.Close()
            if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
        end
    end)
    
    local cancelBtn = CreateThemedButton(contentFrame, CANCEL or "Cancel", 100)
    cancelBtn:SetPoint("BOTTOM", 55, 12)
    cancelBtn:SetScript("OnClick", function()
        dialog.Close()
    end)
    
    dialog:Show()
    titleInput:SetFocus()
end

-- ============================================================================
-- CUSTOM PLAN STORAGE
-- ============================================================================

function WarbandNexus:SaveCustomPlan(title, description, resetType, cycleCount)
    if not self.db.global.customPlans then
        self.db.global.customPlans = {}
    end
    
    local customPlan = {
        id = "custom_" .. time() .. "_" .. math.random(1000, 9999),
        type = "custom",
        name = title,
        source = description or ((ns.L and ns.L["CUSTOM_PLAN_SOURCE"]) or "Custom plan"),
        icon = "Bonus-Objective-Star",  -- Use atlas for custom plans
        iconIsAtlas = true,  -- Mark as atlas
        isCustom = true,
        completed = false,
        resetCycle = (resetType and resetType ~= "none") and {
            enabled = true,
            resetType = resetType,
            lastResetTime = time(),
            totalCycles = cycleCount or 1,
            remainingCycles = cycleCount or 1,
        } or nil,
    }
    
    table.insert(self.db.global.customPlans, customPlan)

    -- Resolve display data immediately so My Plans renders complete info
    if self._ResolveSinglePlan then
        self:_ResolveSinglePlan(customPlan, time())
    end
end

function WarbandNexus:GetCustomPlans()
    return self.db.global.customPlans or {}
end

function WarbandNexus:CompleteCustomPlan(planId)
    if not self.db.global.customPlans then return false end

    for _, plan in ipairs(self.db.global.customPlans) do
        if plan.id == planId then
            if plan.completed then return true end -- Already completed
            
            plan.completed = true
            self:Print(string.format((ns.L and ns.L["CUSTOM_PLAN_COMPLETED"]) or "Custom plan '%s' |cff00ff00completed|r", FormatTextNumbers(plan.name)))

            -- Track completion time for recurring reset
            if plan.resetCycle and plan.resetCycle.enabled then
                plan.resetCycle.completedAt = time()
            end

            -- Fire event immediately so UI refreshes instantly
            self:SendMessage("WN_PLANS_UPDATED", {
                action = "completed",
                planID = plan.id,
            })

            -- Notification deferred slightly so UI refresh completes first
            if self.Notify then
                local planName = FormatTextNumbers(plan.name)
                local planIcon = plan.icon
                C_Timer.After(0.1, function()
                    if WarbandNexus and WarbandNexus.Notify then
                        WarbandNexus:Notify("plan", planName, planIcon)
                    end
                end)
            end

            return true
        end
    end
    return false
end

function WarbandNexus:RemoveCustomPlan(planId)
    if not self.db.global.customPlans then return end
    
    for i, plan in ipairs(self.db.global.customPlans) do
        if plan.id == planId then
            table.remove(self.db.global.customPlans, i)
            break
        end
    end
end

-- ============================================================================
-- WEEKLY VAULT PLAN DIALOG
-- ============================================================================

function WarbandNexus:ShowWeeklyPlanDialog()
    local COLORS = ns.UI_COLORS
    
    -- Get current character info
    local currentName = UnitName("player")
    local currentRealm = GetRealmName()
    
    -- Check if current character already has a weekly plan
    local existingPlan = self:HasActiveWeeklyPlan(currentName, currentRealm)
    
    -- Create external window using helper
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "WeeklyPlanDialog",
        title = (ns.L and ns.L["WEEKLY_VAULT_TRACKER"]) or "Weekly Vault Tracker",
        icon = "Interface\\Icons\\INV_Misc_Note_06",  -- Same as Daily Quest
        width = 500,
        height = existingPlan and 260 or 560
    })
    
    -- If dialog creation failed (duplicate), return
    if not dialog then
        return
    end
    
    -- Content area starts at top of content frame
    local contentY = -12
    
    -- Show existing plan message or creation form
    if existingPlan then
        -- Character already has a weekly plan
        local warningIconFrame3 = CreateIcon(contentFrame, "Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther", 48, false, nil, true)
        warningIconFrame3:SetPoint("TOP", 0, contentY)
        warningIconFrame3:Show()
        local warningIcon = warningIconFrame3.texture
        
        local warningText = FontManager:CreateFontString(contentFrame, "title", "OVERLAY")
        warningText:SetPoint("TOP", warningIcon, "BOTTOM", 0, -15)
        warningText:SetText("|cffff9900" .. ((ns.L and ns.L["WEEKLY_PLAN_EXISTS"]) or "Weekly Plan Already Exists") .. "|r")
        
        local infoText = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        infoText:SetPoint("TOP", warningText, "BOTTOM", 0, -10)
        infoText:SetWidth(440)
        infoText:SetWordWrap(true)
        infoText:SetJustifyH("CENTER")
        local descText = (ns.L and ns.L["WEEKLY_PLAN_EXISTS_DESC"] and string.format(ns.L["WEEKLY_PLAN_EXISTS_DESC"], currentName .. "-" .. currentRealm)) or (currentName .. "-" .. currentRealm .. " already has an active weekly vault plan. You can find it in the 'My Plans' category.")
        infoText:SetText("|cffaaaaaa" .. descText .. "|r")
        
        -- Calculate text height to position button below
        local textHeight = infoText:GetStringHeight()
        
        -- OK button (positioned below text)
        local okBtn = CreateThemedButton(contentFrame, OKAY or "OK", 120)
        okBtn:SetPoint("TOP", infoText, "BOTTOM", 0, -20)
        okBtn:SetScript("OnClick", function()
            dialog.Close()
        end)
    else
        -- Create new weekly plan form
        
        -- Character section with icon (centered) (using Factory pattern)
        local charFrame = ns.UI.Factory:CreateContainer(contentFrame, 300, 45)  -- Narrower, centered width
        charFrame:SetPoint("TOP", 0, -15)  -- Perfectly centered
        
        -- Character race and class info
        local _, currentClass = UnitClass("player")
        local classColors = RAID_CLASS_COLORS[currentClass]
        local _, englishRace = UnitRace("player")
        local gender = UnitSex("player")
        local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
        
        -- Character race icon with border (centered within charFrame) (using Factory pattern)
        local iconContainer = ns.UI.Factory:CreateContainer(charFrame, 36, 36)
        iconContainer:SetPoint("LEFT", 0, 0)  -- Start from left edge
        
        -- Apply border with class color
        if ApplyVisuals then
            if classColors then
                ApplyVisuals(iconContainer, {0.08, 0.08, 0.10, 1}, {classColors.r, classColors.g, classColors.b, 1})
            else
                ApplyVisuals(iconContainer, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8})
            end
        end
        
        -- Character race icon (using atlas)
        local charIconFrame = CreateIcon(iconContainer, raceAtlas, 28, true, nil, true)
        charIconFrame:SetPoint("CENTER", 0, 0)
        charIconFrame:Show()
        
        -- Character name with class color (larger font)
        local charName = FontManager:CreateFontString(charFrame, "title", "OVERLAY")
        charName:SetPoint("LEFT", iconContainer, "RIGHT", 10, 0)
        if classColors then
            charName:SetTextColor(classColors.r, classColors.g, classColors.b)
        else
            charName:SetTextColor(1, 1, 1)
        end
        charName:SetText(currentName .. "-" .. currentRealm)
        
        -- Current progress preview (if API available)
        local progress = self:GetWeeklyVaultProgress(currentName, currentRealm)
        
        -- Fallback: If API not ready, use 0/0/0 progress
        if not progress then
            progress = {
                dungeonCount = 0,
                raidBossCount = 0,
                worldActivityCount = 0
            }
        end
        
        if progress then
            -- Progress header (BIGGER)
            local progressHeader = FontManager:CreateFontString(contentFrame, "header", "OVERLAY", "accent")
            progressHeader:SetPoint("TOP", 0, -85)
            progressHeader:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
            progressHeader:SetText((ns.L and ns.L["CURRENT_PROGRESS"]) or "Current Progress")
            
            -- 4-column progress display (centered) - PREMIUM DASHBOARD
            local colWidth = 108
            local colSpacing = 10
            local totalWidth = colWidth * 3 + colSpacing * 2
            local startX = -(totalWidth / 2) + (colWidth / 2)
            
            local function CreateProgressCol(index, iconAtlas, title, current, thresholds)
                local xPos = startX + (index - 1) * (colWidth + colSpacing)
                
                -- Main column card (using Factory pattern)
                local col = ns.UI.Factory:CreateContainer(contentFrame, colWidth, 150)  -- Increased height for stars
                col:SetPoint("TOP", xPos, -115)
                
                -- Dynamic border color based on progress
                local maxThreshold = thresholds[3] or thresholds[#thresholds]
                local completionRatio = current / maxThreshold
                local borderColor
                
                if completionRatio >= 1.0 then
                    borderColor = {0.2, 0.9, 0.2, 1}  -- Bright green (complete)
                elseif completionRatio >= 0.5 then
                    borderColor = {0.9, 0.8, 0.2, 1}  -- Gold (good progress)
                elseif completionRatio > 0 then
                    borderColor = {0.9, 0.5, 0.2, 1}  -- Orange (started)
                else
                    borderColor = {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6}  -- Gray (not started)
                end
                
                if ApplyVisuals then
                    ApplyVisuals(col, {0.10, 0.10, 0.12, 1}, borderColor)
                end
                
                -- Large icon (centered at top)
                local iconFrame2 = CreateIcon(col, iconAtlas, 38, true, nil, true)
                iconFrame2:SetPoint("TOP", 0, -12)
                iconFrame2:Show()
                
                -- Title (below icon, larger)
                local titleText = FontManager:CreateFontString(col, "title", "OVERLAY")
                titleText:SetPoint("TOP", iconFrame2, "BOTTOM", 0, -8)
                titleText:SetTextColor(0.95, 0.95, 0.95)
                titleText:SetText(title)
                
                -- Reward tier indicators (stars) - Inside card, bigger, with milestone text
                local starCount = #thresholds
                local starSpacing = 42
                local starSize = 24  -- Bigger stars
                local starTotalWidth = (starCount - 1) * starSpacing
                local starStartX = -starTotalWidth / 2
                
                for i = 1, starCount do
                    -- Star container (using Factory pattern)
                    local starContainer = ns.UI.Factory:CreateContainer(col, starSize, starSize + 20)  -- Extra height for text
                    starContainer:SetPoint("TOP", titleText, "BOTTOM", starStartX + (i - 1) * starSpacing, -12)
                    
                    -- Star texture (using Factory pattern)
                    local starFrame = ns.UI.Factory:CreateContainer(starContainer, starSize, starSize)
                    starFrame:SetPoint("TOP", 0, 0)
                    
                    local starTex = starFrame:CreateTexture(nil, "ARTWORK")
                    starTex:SetAllPoints(starFrame)
                    starTex:SetAtlas("PetJournal-FavoritesIcon")
                    
                    -- Check if this milestone is completed
                    local isComplete = current >= thresholds[i]
                    
                    if isComplete then
                        starTex:SetVertexColor(1, 0.9, 0.2)  -- Bright gold (complete)
                    else
                        starTex:SetVertexColor(0.25, 0.25, 0.25)  -- Dark gray (locked)
                    end
                    
                    -- Milestone progress text below star
                    local milestoneText = FontManager:CreateFontString(starContainer, "body", "OVERLAY")
                    milestoneText:SetPoint("TOP", starFrame, "BOTTOM", 0, -3)
                    
                    if isComplete then
                        milestoneText:SetTextColor(0.3, 1, 0.3)  -- Green (complete)
                    else
                        milestoneText:SetTextColor(0.6, 0.6, 0.6)  -- Gray
                    end
                    milestoneText:SetText(string.format("%s / %s", FormatNumber(math.min(current, thresholds[i])), FormatNumber(thresholds[i])))
                end
            end
            
            -- Dungeons (column 1)
            CreateProgressCol(
                1,
                "questlog-questtypeicon-heroic",
                (ns.L and ns.L["MYTHIC_PLUS_LABEL"]) or "Mythic+",
                progress.dungeonCount,
                {1, 4, 8}  -- Thresholds
            )
            
            -- Raids (column 2)
            CreateProgressCol(
                2,
                "questlog-questtypeicon-raid",
                (ns.L and ns.L["RAIDS_LABEL"]) or "Raids",
                progress.raidBossCount,
                {2, 4, 6}  -- Thresholds
            )
            
            -- World (column 3)
            CreateProgressCol(
                3,
                "questlog-questtypeicon-Delves",
                (ns.L and ns.L["QUEST_CAT_WORLD"]) or "World",
                progress.worldActivityCount,
                {2, 4, 8}  -- Thresholds
            )
            
            contentY = contentY - 95
        end
        
        -- === SLOT SELECTION ===
        local slotSelectLabel = FontManager:CreateFontString(contentFrame, "header", "OVERLAY", "accent")
        slotSelectLabel:SetPoint("TOP", 0, -295)
        slotSelectLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        slotSelectLabel:SetText((ns.L and ns.L["TRACK_ACTIVITIES"]) or "Track Activities")
        
        local selectedSlots = { dungeon = true, raid = true, world = true }
        
        local slotOptions = {
            { key = "dungeon", atlas = "questlog-questtypeicon-heroic",  label = (ns.L and ns.L["VAULT_SLOT_DUNGEON"]) or "Dungeon (M+)", color = {0.9, 0.7, 0.2} },
            { key = "raid",    atlas = "questlog-questtypeicon-raid",    label = (ns.L and ns.L["VAULT_SLOT_RAIDS"]) or "Raids",          color = {0.3, 0.8, 1.0} },
            { key = "world",   atlas = "questlog-questtypeicon-Delves",  label = (ns.L and ns.L["VAULT_SLOT_WORLD"]) or "World",          color = {0.4, 0.9, 0.4} },
        }
        
        local slotCheckY = -320
        local slotCheckSpacing = 30
        for si, opt in ipairs(slotOptions) do
            local rowFrame = CreateFrame("Frame", nil, contentFrame)
            rowFrame:SetSize(300, 24)
            rowFrame:SetPoint("TOP", 0, slotCheckY + (si - 1) * -slotCheckSpacing)
            
            local cb = CreateThemedCheckbox(rowFrame, true)
            cb:SetPoint("LEFT", 0, 0)
            
            local colorBar = rowFrame:CreateTexture(nil, "ARTWORK")
            colorBar:SetSize(3, 18)
            colorBar:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            colorBar:SetColorTexture(opt.color[1], opt.color[2], opt.color[3], 0.9)
            
            local icon = rowFrame:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", colorBar, "RIGHT", 6, 0)
            icon:SetAtlas(opt.atlas, false)
            
            local lbl = FontManager:CreateFontString(rowFrame, "body", "OVERLAY")
            lbl:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            lbl:SetText(opt.label)
            lbl:SetTextColor(1, 1, 1)
            
            local capturedKey = opt.key
            cb:SetScript("OnClick", function(self)
                local checked = self:GetChecked()
                selectedSlots[capturedKey] = checked
                if self.innerDot then self.innerDot:SetShown(checked) end
            end)
        end
        
        -- Buttons (symmetrically centered)
        local createBtn = CreateThemedButton(contentFrame, (ns.L and ns.L["CREATE_PLAN"]) or "Create Plan", 120)
        createBtn:SetPoint("BOTTOM", -65, 8)
        createBtn:SetScript("OnClick", function()
            -- Create the weekly plan with selected slots
            local plan = self:CreateWeeklyPlan(currentName, currentRealm, selectedSlots)
            if plan then
                -- Refresh UI to show new plan
                if self.RefreshUI then
                    self:RefreshUI()
                end
                
                -- Close dialog
                dialog.Close()
            end
        end)
        
        local cancelBtn = CreateThemedButton(contentFrame, CANCEL or "Cancel", 120)
        cancelBtn:SetPoint("BOTTOM", 65, 8)
        cancelBtn:SetScript("OnClick", function()
            dialog.Close()
        end)
    end
    
    dialog:Show()
end

-- ============================================================================
-- CLOSE ALL PLAN DIALOGS
-- ============================================================================

function WarbandNexus:CloseAllPlanDialogs()
    -- Close Weekly Plan Dialog
    if _G["WarbandNexus_WeeklyPlanDialog"] and _G["WarbandNexus_WeeklyPlanDialog"].Close then
        _G["WarbandNexus_WeeklyPlanDialog"].Close()
    end
    
    -- Close Daily Plan Dialog
    if _G["WarbandNexus_DailyPlanDialog"] and _G["WarbandNexus_DailyPlanDialog"].Close then
        _G["WarbandNexus_DailyPlanDialog"].Close()
    end
    
    -- Close Custom Plan Dialog
    if _G["WarbandNexus_CustomPlanDialog"] and _G["WarbandNexus_CustomPlanDialog"].Close then
        _G["WarbandNexus_CustomPlanDialog"].Close()
    end
end

-- ============================================================================
-- DAILY QUEST PLAN DIALOG
-- ============================================================================

function WarbandNexus:ShowDailyPlanDialog()
    local COLORS = ns.UI_COLORS
    local CAT_DISPLAY = ns.CATEGORY_DISPLAY or {}
    
    local currentName = UnitName("player")
    local currentRealm = GetRealmName()
    local _, currentClass = UnitClass("player")
    local classColors = RAID_CLASS_COLORS[currentClass]
    
    local existingPlan = self:HasActiveDailyPlan(currentName, currentRealm)
    
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "DailyPlanDialog",
        title = (ns.L and ns.L["DAILY_QUEST_TRACKER"]) or "Midnight Quest Tracker",
        icon = "Interface\\Icons\\INV_Misc_Note_06",
        width = 460,
        height = existingPlan and 220 or 470,
    })
    
    if not dialog then return end
    
    -- Existing plan warning
    if existingPlan then
        local warningIconFrame = CreateIcon(contentFrame, "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew", 40, false, nil, true)
        warningIconFrame:SetPoint("TOP", 0, -30)
        warningIconFrame:Show()
        
        local warningText = FontManager:CreateFontString(contentFrame, "title", "OVERLAY")
        warningText:SetPoint("TOP", warningIconFrame, "BOTTOM", 0, -10)
        warningText:SetText("|cffff9900" .. ((ns.L and ns.L["DAILY_PLAN_EXISTS"]) or "Plan Already Exists") .. "|r")
        
        local infoText = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        infoText:SetPoint("TOP", warningText, "BOTTOM", 0, -8)
        infoText:SetWidth(400)
        infoText:SetWordWrap(true)
        infoText:SetJustifyH("CENTER")
        infoText:SetText("|cffaaaaaa" .. currentName .. "-" .. currentRealm .. " already has an active quest plan.|r")
        
        local okBtn = CreateThemedButton(contentFrame, OKAY or "OK", 120)
        okBtn:SetPoint("TOP", infoText, "BOTTOM", 0, -16)
        okBtn:SetScript("OnClick", function() dialog.Close() end)
        
        dialog:Show()
        return
    end
    
    -- Character display
    local charFrame = ns.UI.Factory:CreateContainer(contentFrame, 420, 42)
    charFrame:SetPoint("TOP", 0, -12)
    
    local _, englishRace = UnitRace("player")
    local gender = UnitSex("player")
    local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
    
    local iconContainer = ns.UI.Factory:CreateContainer(charFrame, 32, 32)
    iconContainer:SetPoint("LEFT", 10, 0)
    if ApplyVisuals and classColors then
        ApplyVisuals(iconContainer, {0.08, 0.08, 0.10, 1}, {classColors.r, classColors.g, classColors.b, 1})
    end
    
    local charIconFrame = CreateIcon(iconContainer, raceAtlas, 26, true, nil, true)
    charIconFrame:SetPoint("CENTER")
    charIconFrame:Show()
    
    local charText = FontManager:CreateFontString(charFrame, "title", "OVERLAY")
    charText:SetPoint("LEFT", iconContainer, "RIGHT", 8, 0)
    if classColors then charText:SetTextColor(classColors.r, classColors.g, classColors.b) end
    charText:SetText(currentName .. "-" .. currentRealm)
    
    -- "Midnight" content label
    local contentLabel = FontManager:CreateFontString(charFrame, "small", "OVERLAY")
    contentLabel:SetPoint("RIGHT", -10, 0)
    contentLabel:SetText("|cff888888Midnight|r")
    
    -- Quest type checkboxes
    local selectedQuestTypes = {
        weeklyQuests = true,
        worldQuests  = true,
        dailyQuests  = true,
        assignments  = true,
        events       = true,
    }
    
    local questTypeY = -68
    local sectionLabel = FontManager:CreateFontString(contentFrame, "subtitle", "OVERLAY", "accent")
    sectionLabel:SetPoint("TOPLEFT", 16, questTypeY)
    sectionLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    sectionLabel:SetText((ns.L and ns.L["QUEST_TYPES"]) or "Track Categories:")
    
    local CATEGORIES = ns.QUEST_CATEGORIES or {}
    local categoryDescs = {
        weeklyQuests = "Weekly objectives, hunts, sparks, world boss, delves",
        worldQuests  = "Zone-wide repeatable world quests",
        dailyQuests  = "Daily repeatable quests from NPCs",
        assignments  = "Special assignments and bounties",
        events       = "Bonus objectives, tasks, and activities",
    }
    
    for i, catInfo in ipairs(CATEGORIES) do
        local catKey = catInfo.key
        local display = CAT_DISPLAY[catKey] or {}
        local catColor = display.color or {0.8, 0.8, 0.8}
        local catName = display.name and display.name() or catKey
        
        local cb = CreateThemedCheckbox(contentFrame, selectedQuestTypes[catKey])
        cb:SetPoint("TOPLEFT", 16, questTypeY - 28 - (i - 1) * 46)
        
        local colorBar = contentFrame:CreateTexture(nil, "ARTWORK")
        colorBar:SetSize(3, 30)
        colorBar:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        colorBar:SetColorTexture(catColor[1], catColor[2], catColor[3], 0.9)
        
        local label = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        label:SetPoint("LEFT", colorBar, "RIGHT", 6, 5)
        label:SetText(catName)
        
        local desc = FontManager:CreateFontString(contentFrame, "small", "OVERLAY")
        desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        desc:SetTextColor(0.6, 0.6, 0.6)
        desc:SetText(categoryDescs[catKey] or "")
        
        cb:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            selectedQuestTypes[catKey] = isChecked
            if self.innerDot then self.innerDot:SetShown(isChecked) end
        end)
    end
    
    -- Buttons
    local createBtn = CreateThemedButton(contentFrame, (ns.L and ns.L["CREATE_PLAN"]) or "Track Character", 140)
    createBtn:SetPoint("BOTTOM", -75, 10)
    createBtn:SetScript("OnClick", function()
        local plan = self:CreateDailyPlan(currentName, currentRealm, selectedQuestTypes)
        if plan then
            if self.RefreshUI then self:RefreshUI() end
            dialog.Close()
        end
    end)
    
    local cancelBtn = CreateThemedButton(contentFrame, CANCEL or "Cancel", 100)
    cancelBtn:SetPoint("BOTTOM", 75, 10)
    cancelBtn:SetScript("OnClick", function() dialog.Close() end)
    
    dialog:Show()
end

-- ============================================================================
-- TRANSMOG BROWSER
-- ============================================================================

-- Module state for transmog browser
local currentTransmogSubCategory = "all"
local transmogResults = {}
local transmogLoading = false
local transmogLoadAttempted = false  -- Track if we've tried to load at least once
local transmogLoadProgress = {current = 0, total = 0, message = ""}
local transmogSearchText = ""  -- Search query text
local transmogCache = {}  -- Cache results per category: {categoryKey = {results, timestamp}}

--[[
    Draw transmog browser with sub-category filters
    @param parent Frame - Parent frame
    @param yOffset number - Current Y offset
    @param width number - Width of parent
    @return number - New Y offset
]]
function WarbandNexus:DrawTransmogBrowser(parent, yOffset, width)
    local COLORS = ns.UI_COLORS
    
    -- Work in Progress screen (full area, not centered)
    local wipCard = CreateCard(parent, 230)
    
    -- Anchor to top, stretch horizontally (like other content)
    wipCard:SetPoint("TOPLEFT", 10, -(yOffset + 10))
    wipCard:SetPoint("TOPRIGHT", -10, -(yOffset + 10))
    wipCard:SetHeight(230)
    
    local wipIconFrame2 = CreateIcon(wipCard, "Interface\\Icons\\INV_Misc_EngGizmos_20", 64, false, nil, true)
    wipIconFrame2:SetPoint("CENTER", wipCard, "CENTER", 0, 40)  -- Move icon slightly up from center
    local wipIcon = wipIconFrame2.texture
    
    local wipTitle = FontManager:CreateFontString(wipCard, "header", "OVERLAY", "accent")
    wipTitle:SetPoint("TOP", wipIcon, "BOTTOM", 0, -20)
    wipTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    wipTitle:SetText((ns.L and ns.L["WORK_IN_PROGRESS"]) or "Work in Progress")
    
    local wipDesc = FontManager:CreateFontString(wipCard, "body", "OVERLAY")
    wipDesc:SetPoint("TOP", wipTitle, "BOTTOM", 0, -15)
    wipDesc:SetWidth(width - 100)
    wipDesc:SetTextColor(1, 1, 1)  -- White
    wipDesc:SetJustifyH("CENTER")
    wipDesc:SetText((ns.L and ns.L["TRANSMOG_WIP_DESC"]) or "Transmog collection tracking is currently under development.\n\nThis feature will be available in a future update with improved\nperformance and better integration with Warband systems.")
    
    -- CRITICAL: Show the card and icon!
    wipCard:Show()
    wipIconFrame2:Show()
    
    return yOffset + 250  -- Return yOffset + card height + spacing
end

