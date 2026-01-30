--[[
    Warband Nexus - Plans Tab UI
    User-driven goal tracker for mounts, pets, and toys
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

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
local CreateResultsContainer = ns.UI_CreateResultsContainer
local CreateIcon = ns.UI_CreateIcon
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor
local CreateExternalWindow = ns.UI_CreateExternalWindow
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local CreateTableRow = ns.UI_CreateTableRow
local CreateExpandableRow = ns.UI_CreateExpandableRow
local CreateCategorySection = ns.UI_CreateCategorySection
local CardLayoutManager = ns.UI_CardLayoutManager

-- Loading state for collection scanning (per-category)
ns.PlansLoadingState = ns.PlansLoadingState or {
    -- Structure: { mount = { isLoading, loader }, pet = { isLoading, loader }, toy = { isLoading, loader } }
}
local PlanCardFactory = ns.UI_PlanCardFactory
local FormatNumber = ns.UI_FormatNumber
local FormatTextNumbers = ns.UI_FormatTextNumbers

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

-- Category definitions (using atlas icons from PlanCardFactory)
local CATEGORIES = {
    { key = "active", name = "My Plans", icon = "Interface\\Icons\\INV_Misc_Map_01" },  -- Keep original for My Plans
    { key = "daily_tasks", name = "Daily Tasks", icon = "Interface\\Icons\\INV_Misc_Note_06" },  -- Keep original for Daily Tasks
    { key = "mount", name = "Mounts", iconAtlas = "dragon-rostrum" },
    { key = "pet", name = "Pets", iconAtlas = "WildBattlePetCapturable" },
    { key = "toy", name = "Toys", iconAtlas = "CreationCatalyst-32x32" },
    { key = "transmog", name = "Transmog", iconAtlas = "poi-transmogrifier" },
    { key = "illusion", name = "Illusions", iconAtlas = "UpgradeItem-32x32" },
    { key = "title", name = "Titles", iconAtlas = "poi-legendsoftheharanir" },
    { key = "achievement", name = "Achievements", icon = "Interface\\Icons\\Achievement_General" },  -- Keep original for Achievements
}

-- Module state
local currentCategory = "active"
local searchText = ""
local showCompleted = false  -- Default: show only active plans (not completed)

-- Event listener for collection scan progress (refresh UI during achievement scan)
local eventsRegistered = false
local lastUIRefresh = 0  -- Track last UI refresh time
local function RegisterCollectionScanEvents()
    if eventsRegistered then
        return
    end
    
    if not WarbandNexus or not WarbandNexus.RegisterMessage then
        print("|cffff0000[WN PlansUI]|r Cannot register scan events - WarbandNexus not ready")
        return
    end
    
    local Constants = ns.Constants
    if not Constants or not Constants.EVENTS then
        print("|cffff0000[WN PlansUI]|r Cannot register scan events - Constants not ready")
        return
    end
    
    print("|cff9370DB[WN PlansUI]|r Registering collection scan event listeners...")
    
    -- Listen for scan progress (refresh UI to update progress bar)
    -- GENERIC: Works for all collection types (mount, pet, toy, achievement)
    WarbandNexus:RegisterMessage(Constants.EVENTS.COLLECTION_SCAN_PROGRESS, function(event, data)
        -- OPTIMIZATION: Throttle UI refreshes (max 1 refresh per 500ms)
        local currentTime = debugprofilestop()
        local timeSinceLastRefresh = currentTime - lastUIRefresh
        
        -- Only refresh if enough time passed AND we're on the right tab
        if timeSinceLastRefresh < 500 then
            return  -- Skip this refresh (too soon)
        end
        
        -- Only refresh if we're on Plans tab AND the scanned category matches current view
        if WarbandNexus.UI and WarbandNexus.UI.mainFrame then
            local mainFrame = WarbandNexus.UI.mainFrame
            local scanCategory = data and data.category
            
            -- Refresh if:
            -- 1. On Plans tab
            -- 2. Current category matches scan category OR viewing "My Plans" (which includes all)
            if mainFrame:IsShown() and mainFrame.currentTab == "plans" and 
               (currentCategory == scanCategory or currentCategory == "my_plans") then
                print("|cff00ccff[WN PlansUI]|r Scan progress (" .. tostring(scanCategory) .. "): " .. (data and data.progress or 0) .. "%")
                lastUIRefresh = currentTime
                
                -- CRITICAL FIX: Defer UI refresh to prevent freezing during scans
                C_Timer.After(0.05, function()
                    if WarbandNexus and WarbandNexus.RefreshUI then
                        WarbandNexus:RefreshUI()
                    end
                end)
            end
        end
    end)
    
    -- Listen for scan complete (final refresh)
    -- GENERIC: Works for all collection types (mount, pet, toy, achievement)
    WarbandNexus:RegisterMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, function(event, data)
        local scanCategory = data and data.category
        print("|cff00ff00[WN PlansUI]|r " .. tostring(scanCategory) .. " scan complete!")
        
        -- Refresh Plans UI if viewing relevant category
        if WarbandNexus.UI and WarbandNexus.UI.mainFrame then
            local mainFrame = WarbandNexus.UI.mainFrame
            
            -- Refresh if on Plans tab AND (viewing scanned category OR "My Plans")
            if mainFrame:IsShown() and mainFrame.currentTab == "plans" and
               (currentCategory == scanCategory or currentCategory == "my_plans") then
                print("|cff9370DB[WN PlansUI]|r Refreshing UI to show " .. tostring(scanCategory) .. " results...")
                
                -- CRITICAL FIX: Defer UI refresh to prevent freezing
                C_Timer.After(0.1, function()
                    if WarbandNexus and WarbandNexus.RefreshUI then
                        WarbandNexus:RefreshUI()
                    end
                end)
            end
        end
    end)
    
    eventsRegistered = true
    print("|cff00ff00[WN PlansUI]|r Event listeners registered successfully!")
end

-- Register events when module loads (immediate, not delayed)
RegisterCollectionScanEvents()

-- Also try registering on PLAYER_ENTERING_WORLD (backup)
if WarbandNexus and WarbandNexus.RegisterEvent then
    WarbandNexus:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(2, RegisterCollectionScanEvents)
    end)
end

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
    
    -- Determine source type (use cleaned source for all checks)
    if cleanSource:find("Vendor") or cleanSource:find("Sold by") then
        parts.sourceType = "Vendor"
        parts.isVendor = true
    elseif cleanSource:find("Drop") then
        parts.sourceType = "Drop"
        parts.isDrop = true
    elseif cleanSource:find("Pet Battle") then
        parts.sourceType = "Pet Battle"
        parts.isPetBattle = true
    elseif cleanSource:find("Quest") then
        parts.sourceType = "Quest"
        parts.isQuest = true
    elseif cleanSource:find("Achievement") then
        parts.sourceType = "Achievement"
    elseif cleanSource:find("Profession") or cleanSource:find("Crafted") then
        parts.sourceType = "Crafted"
    elseif cleanSource:find("Promotion") or cleanSource:find("Blizzard") then
        parts.sourceType = "Promotion"
    elseif cleanSource:find("Trading Post") then
        parts.sourceType = "Trading Post"
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
        parts.cost = goldCost .. " Gold"
    end
    
    -- Extract cost (other currencies) - use cleaned source
    local currencyCost = cleanSource:match("Cost:%s*([%d,]+)%s*([^\n]+)")
    if currencyCost and not goldCost then
        parts.cost = currencyCost
    end
    
    -- Extract renown requirement - use cleaned source
    local renown = cleanSource:match("Renown%s*(%d+)") or cleanSource:match("Renown:%s*(%d+)")
    if renown then
        parts.renown = "Renown " .. renown
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
    
    local yOffset = 8
    local width = parent:GetWidth() - 20
    
    -- Check if module is enabled (early check for buttons)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.plans ~= false
    
    -- Initialize expanded cards state (persist across refreshes)
    if not ns.expandedCards then
        ns.expandedCards = {}
    end
    
    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
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
            local progress = self:CheckPlanProgress(plan)
            if not (progress and progress.collected) then
                activePlanCount = activePlanCount + 1
            end
        end
    end
    
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleTextContent = "|cff" .. hexColor .. "Collection Plans|r"
    local subtitleTextContent = "Track your collection goals • " .. FormatNumber(activePlanCount) .. " active plan" .. (activePlanCount ~= 1 and "s" or "")
    
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
        local addCustomBtn = CreateThemedButton(titleCard, "Add Custom", 100)
        addCustomBtn:SetPoint("RIGHT", -15, 0)
        -- Store reference for state management
        self.addCustomBtn = addCustomBtn
        addCustomBtn:SetScript("OnClick", function()
            self:ShowCustomPlanDialog()
        end)
        
        -- Add Vault button (using shared widget)
        local addWeeklyBtn = CreateThemedButton(titleCard, "Add Vault", 100)
        addWeeklyBtn:SetPoint("RIGHT", addCustomBtn, "LEFT", -8, 0)
        addWeeklyBtn:SetScript("OnClick", function()
            self:ShowWeeklyPlanDialog()
        end)
        
        -- Add Quest button (using shared widget) - DISABLED (Work in Progress)
        local addDailyBtn = CreateThemedButton(titleCard, "Add Quest", 100)
        addDailyBtn:SetPoint("RIGHT", addWeeklyBtn, "LEFT", -8, 0)
        addDailyBtn:Enable(false)  -- Disable button
        
        -- Dim the button visually
        if addDailyBtn.bg then
            addDailyBtn.bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)  -- Darker, semi-transparent
        end
        
        -- Add warning icon overlay
        local wipIcon = addDailyBtn:CreateTexture(nil, "OVERLAY")
        wipIcon:SetSize(16, 16)
        wipIcon:SetPoint("LEFT", 6, 0)
        wipIcon:SetAtlas("icons_64x64_important")
        wipIcon:SetVertexColor(1, 0.7, 0)  -- Orange warning color
        
        -- Reposition text to the right of the icon (centered alignment)
        if addDailyBtn.text then
            addDailyBtn.text:ClearAllPoints()
            addDailyBtn.text:SetPoint("LEFT", wipIcon, "RIGHT", 4, 0)  -- 4px spacing from icon
            addDailyBtn.text:SetTextColor(0.5, 0.5, 0.5)  -- Gray text
        end
        
        -- Checkbox (using shared widget) - Next to Add Quest button
        local checkbox = CreateThemedCheckbox(titleCard, showCompleted)
        if not checkbox then
            print("|cffff0000WN DEBUG: CreateThemedCheckbox returned nil! titleCard:|r", titleCard)
            return
        end
        
        if not checkbox.HasScript then
            print("|cffff0000WN DEBUG: Checkbox missing HasScript method! Type:|r", checkbox:GetObjectType())
        elseif not checkbox:HasScript("OnClick") then
            print("|cffffff00WN DEBUG: Checkbox type", checkbox:GetObjectType(), "doesn't support OnClick|r")
        end
        
        checkbox:SetPoint("RIGHT", addDailyBtn, "LEFT", -10, 0)
        
        -- Add text label for checkbox (left of checkbox)
        local checkboxLabel = FontManager:CreateFontString(titleCard, "body", "OVERLAY")
        checkboxLabel:SetPoint("RIGHT", checkbox, "LEFT", -8, 0)
        checkboxLabel:SetText("Show Completed")
        checkboxLabel:SetTextColor(0.9, 0.9, 0.9)
        
        -- Override OnClick to add filtering (with safety check)
        local originalOnClick = nil
        if checkbox and checkbox.GetScript then
            local success, result = pcall(function() return checkbox:GetScript("OnClick") end)
            if success then
                originalOnClick = result
            else
                print("WarbandNexus DEBUG: GetScript('OnClick') failed for checkbox:", result)
            end
        end
        checkbox:SetScript("OnClick", function(self)
            if originalOnClick then originalOnClick(self) end
            showCompleted = self:GetChecked() -- When checked, show ONLY completed plans
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
    end
    
    -- Check if module is disabled (before showing controls)
    if not moduleEnabled then
        titleCard:Show()
        yOffset = yOffset + GetLayout().afterHeader
        
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, "Collection Plans")
        return yOffset + cardHeight
    end
    
    titleCard:Show()
    
    yOffset = yOffset + GetLayout().afterHeader  -- Standard spacing after title card
    
    -- Register event listener for plan updates (only once)
    if not self._plansEventRegistered then
        if self.RegisterMessage then
            self:RegisterMessage("WN_PLANS_UPDATED", "OnPlansUpdated")
        end
        self._plansEventRegistered = true
    end
    
    -- ===== CATEGORY BUTTONS (using Factory pattern) =====
    local categoryBar = ns.UI.Factory:CreateContainer(parent, nil, nil, false)  -- NO BORDER
    categoryBar:SetPoint("TOPLEFT", 10, -yOffset)
    categoryBar:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local catBtnWidth = 150
    local catBtnHeight = 40
    local catBtnSpacing = 8
    local maxWidth = parent:GetWidth() - 20  -- Available width
    
    local currentX = 0
    local currentRow = 0
    
    for i, cat in ipairs(CATEGORIES) do
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
        
        -- Apply background ONLY (NO BORDER for category buttons)
        if btn.SetBackdrop then
            Mixin(btn, BackdropTemplateMixin)
            btn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
            btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
        end
        
        -- Apply highlight effect (safe check for Factory)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end
        
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
        label:SetTextColor(1, 1, 1)  -- White
        
        -- Update border color based on active state
        if UpdateBorderColor then
            if isActive then
                -- Active state - full accent color
                UpdateBorderColor(btn, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
                if btn.SetBackdropColor then
                    btn:SetBackdropColor(COLORS.accent[1] * 0.3, COLORS.accent[2] * 0.3, COLORS.accent[3] * 0.3, 1)
                end
            else
                -- Inactive state - dimmed accent color
                UpdateBorderColor(btn, {COLORS.accent[1] * 0.6, COLORS.accent[2] * 0.6, COLORS.accent[3] * 0.6, 1})
                if btn.SetBackdropColor then
                    btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
                end
            end
        end
        
        btn:SetScript("OnClick", function()
            currentCategory = cat.key
            searchText = ""
            browseResults = {}
            
            -- CRITICAL FIX: Defer UI refresh to next frame to prevent button freeze
            -- This allows the click handler to complete before UI is redrawn
            C_Timer.After(0.05, function()
                if not self or not self.RefreshUI then return end
                self:RefreshUI()
            end)
        end)
        
        -- Update X position for next button
        currentX = currentX + catBtnWidth + catBtnSpacing
    end
    
    -- Set categoryBar height based on rows
    local totalHeight = (currentRow + 1) * (catBtnHeight + catBtnSpacing)
    categoryBar:SetHeight(totalHeight)
    
    yOffset = yOffset + totalHeight + 8
    
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

function WarbandNexus:DrawActivePlans(parent, yOffset, width, category)
    local plans = self:GetActivePlans()
    
    -- Filter by category first
    if category == "daily_tasks" then
        local dailyPlans = {}
        for _, plan in ipairs(plans) do
            if plan.type == "daily_quests" then
                table.insert(dailyPlans, plan)
            end
        end
        plans = dailyPlans
    elseif category == "active" then
        -- For "active" (My Plans), exclude daily_quests (they have their own tab)
        local activePlans = {}
        for _, plan in ipairs(plans) do
            if plan.type ~= "daily_quests" then
                table.insert(activePlans, plan)
            end
        end
        plans = activePlans
    end
    
    -- Sort plans: Weekly vault plans first, then others
    table.sort(plans, function(a, b)
        if a.type == "weekly_vault" and b.type ~= "weekly_vault" then
            return true
        elseif a.type ~= "weekly_vault" and b.type == "weekly_vault" then
            return false
        else
            -- Ensure both IDs are numbers for comparison
            local aID = tonumber(a.id) or 0
            local bID = tonumber(b.id) or 0
            return aID < bID
        end
    end)
    
    -- #region agent log
    print(string.format("[DEBUG H5-Plans] Total plans before filter: %d", #plans))
    -- #endregion
    
    -- Filter plans based on showCompleted flag
    local filteredPlans = {}
    for _, plan in ipairs(plans) do
        local isComplete = false
        
        -- Check completion based on plan type
        if plan.type == "weekly_vault" then
            -- Weekly vault: check fullyCompleted flag
            isComplete = plan.fullyCompleted == true
        elseif plan.type == "daily_quests" then
            -- Daily quests: check if all quests are complete
            local totalQuests = 0
            local completedQuests = 0
            for category, questList in pairs(plan.quests or {}) do
                if plan.questTypes[category] then
                    for _, quest in ipairs(questList) do
                        totalQuests = totalQuests + 1
                        if quest.isComplete then
                            completedQuests = completedQuests + 1
                        end
                    end
                end
            end
            isComplete = (totalQuests > 0 and completedQuests == totalQuests)
        else
            -- Regular collection plans: use CheckPlanProgress
            local progress = self:CheckPlanProgress(plan)
            isComplete = (progress and progress.collected)
        end
        
        -- Filter based on showCompleted flag
        if showCompleted then
            -- Show ONLY completed plans
            if isComplete then
                table.insert(filteredPlans, plan)
            end
        else
            -- Show ONLY active/incomplete plans (default)
            if not isComplete then
                table.insert(filteredPlans, plan)
            end
        end
    end
    plans = filteredPlans
    
    if #plans == 0 then
        -- Empty state card with plans icon (taller card, centered content)
        local cardHeight = 180
        local emptyCard = CreateCard(parent, cardHeight)
        emptyCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
        emptyCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
        
        -- Container for vertical centering
        local contentY = cardHeight / 2 - 50  -- Center vertically
        
        -- Plans icon (from category icons)
        local iconFrame = CreateIcon(emptyCard, "Interface\\Icons\\INV_Misc_Map_01", 64, false, nil, true)
        iconFrame:SetPoint("TOP", 0, -contentY)
        iconFrame.texture:SetDesaturated(true)
        iconFrame.texture:SetAlpha(0.5)
        iconFrame:Show()
        
        -- Title
        local title = FontManager:CreateFontString(emptyCard, "title", "OVERLAY")
        title:SetPoint("TOP", iconFrame, "BOTTOM", 0, -15)
        title:SetText("|cffffffffNo planned activity|r")
        
        -- Description
        local desc = FontManager:CreateFontString(emptyCard, "body", "OVERLAY")
        desc:SetPoint("TOP", title, "BOTTOM", 0, -10)
        desc:SetTextColor(0.7, 0.7, 0.7)
        desc:SetText("Click on Mounts, Pets, or Toys above to browse and add goals!")
        
        emptyCard:Show()
        
        return yOffset + cardHeight + 10
    end
    
    -- === 2-COLUMN CARD GRID (matching browse view) ===
    local cardSpacing = 8
    local cardWidth = (width - cardSpacing) / 2
    local cardHeight = 130  -- Standard height for all plan cards
    
    -- Initialize CardLayoutManager for dynamic card positioning
    local layoutManager = CardLayoutManager:Create(parent, 2, cardSpacing, yOffset)
    
    -- Add resize handler to parent frame to refresh layout when window is resized
    if not parent._layoutManagerResizeHandler then
        parent:SetScript("OnSizeChanged", function(self)
            -- Refresh all layout managers attached to this parent
            if layoutManager then
                CardLayoutManager:RefreshLayout(layoutManager)
            end
        end)
        parent._layoutManagerResizeHandler = true
    end
    
    for i, plan in ipairs(plans) do
        local progress = self:CheckPlanProgress(plan)
        
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
            
            -- Apply green border
            if ApplyVisuals then
                local borderColor = {0.30, 0.90, 0.30, 0.8}
                ApplyVisuals(card, {0.08, 0.08, 0.10, 1}, borderColor)
            end
            
            -- Create weekly vault content via factory
            PlanCardFactory:CreateWeeklyVaultCard(card, plan, progress, nil)
            
            card:Show()
        
        -- === DAILY QUEST PLANS (Individual Quest Cards) ===
        elseif plan.type == "daily_quests" then
            -- Header card with plan info (full width)
            local headerHeight = 80
            local headerCard = CreateCard(parent, headerHeight)
            headerCard:EnableMouse(true)
            
            -- Add to layout manager as column 0 (for tracking), but will be full width
            local headerYPos = CardLayoutManager:AddCard(layoutManager, headerCard, 0, headerHeight)
            
            -- Override positioning to make it full width
            headerCard:ClearAllPoints()
            headerCard:SetPoint("TOPLEFT", 10, -headerYPos)
            headerCard:SetPoint("TOPRIGHT", -10, -headerYPos)
            
            -- Update layout manager for full-width header card (update both columns to same Y)
            layoutManager.currentYOffsets[0] = headerYPos + headerHeight + cardSpacing
            layoutManager.currentYOffsets[1] = headerYPos + headerHeight + cardSpacing
            
            -- Mark card as full width for layout recalculation
            if headerCard._layoutInfo then
                headerCard._layoutInfo.isFullWidth = true
            end
            
            -- NO BORDER for header (clean look)
            if headerCard.BorderTop then
                headerCard.BorderTop:Hide()
                headerCard.BorderBottom:Hide()
                headerCard.BorderLeft:Hide()
                headerCard.BorderRight:Hide()
            end
            
            -- Get character class color
            local classColor = {1, 1, 1}
            if plan.characterClass then
                local classColors = RAID_CLASS_COLORS[plan.characterClass]
                if classColors then
                    classColor = {classColors.r, classColors.g, classColors.b}
                end
            end
            
            -- === HEADER (using Factory pattern) ===
            local iconBorder = ns.UI.Factory:CreateContainer(headerCard, 42, 42)
            iconBorder:SetPoint("LEFT", 10, 0)
            -- Icon border removed (naked frame)
            -- Icon border removed (naked frame)
            
            local iconFrameObj = CreateIcon(headerCard, plan.icon, 38, false, nil, false)
            iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
            
            -- Title
            local titleText = FontManager:CreateFontString(headerCard, "body", "OVERLAY", "accent")
            titleText:SetPoint("LEFT", iconBorder, "RIGHT", 10, 10)
            titleText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
            titleText:SetText("Daily Tasks - " .. (plan.contentName or "Unknown"))
            
            -- Character name
            local charText = FontManager:CreateFontString(headerCard, "small", "OVERLAY")
            charText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
            charText:SetTextColor(classColor[1], classColor[2], classColor[3])
            charText:SetText(plan.characterName)
            
            -- Quest count summary
            local totalQuests = 0
            local completedQuests = 0
            for category, questList in pairs(plan.quests or {}) do
                if plan.questTypes[category] then
                    for _, quest in ipairs(questList) do
                        totalQuests = totalQuests + 1
                        if quest.isComplete then
                            completedQuests = completedQuests + 1
                        end
                    end
                end
            end
            
            local summaryText = FontManager:CreateFontString(headerCard, "title", "OVERLAY")
            summaryText:SetPoint("RIGHT", -50, 0)
            if completedQuests == totalQuests and totalQuests > 0 then
                summaryText:SetTextColor(0.3, 1, 0.3)
            else
                summaryText:SetTextColor(1, 1, 1)
            end
            summaryText:SetText(string.format("%s/%s", FormatNumber(completedQuests), FormatNumber(totalQuests)))
            
            -- Remove button (using Factory pattern)
            local removeBtn = ns.UI.Factory:CreateButton(headerCard, 16, 16)
            removeBtn:SetPoint("TOPRIGHT", -6, -6)
            local removeBtnText = FontManager:CreateFontString(removeBtn, "body", "OVERLAY")
            removeBtnText:SetPoint("CENTER")
            removeBtnText:SetText("|cffff6060×|r")
            -- Font size managed by FontManager (uses "title" category ~16px with scale)
            local font, size = removeBtnText:GetFont()
            removeBtnText:SetFont(font, size, "THICKOUTLINE")  -- Only apply outline, keep size
            removeBtn:SetScript("OnClick", function()
                self:RemovePlan(plan.id)
                if self.RefreshUI then
                    self:RefreshUI()
                end
            end)
            
            -- === INDIVIDUAL QUEST CARDS (Same design as other plans) ===
            
            -- Debug: Log selected quest types
            local selectedTypes = {}
            for catKey, enabled in pairs(plan.questTypes or {}) do
                if enabled then
                    table.insert(selectedTypes, catKey)
                end
            end
            
            headerCard:Show()
            
            local categoryOrder = {"dailyQuests", "worldQuests", "weeklyQuests", "assignments"}
            local categoryInfo = {
                dailyQuests = {name = "Daily", atlas = "quest-recurring-available", color = {1, 0.9, 0.3}},
                worldQuests = {name = "World", atlas = "worldquest-tracker-questmarker", color = {0.3, 0.8, 1}},
                weeklyQuests = {name = "Weekly", atlas = "quest-legendary-available", color = {1, 0.5, 0.2}},
                assignments = {name = "Assignment", atlas = "quest-important-available", color = {0.8, 0.3, 1}}
            }
            
            local questCardWidth = (width - 8) / 2  -- 2 columns, same as browse cards
            local questCardHeight = 130  -- Same height as browse cards
            local questCardIndex = 0
            local hasQuests = false
            
            for _, catKey in ipairs(categoryOrder) do
                if plan.questTypes[catKey] and plan.quests[catKey] then
                    
                    for _, quest in ipairs(plan.quests[catKey]) do
                        if not quest.isComplete then
                            hasQuests = true
                            local catData = categoryInfo[catKey]
                            
                            -- Determine column (alternate between 0 and 1)
                            local questCol = questCardIndex % 2
                            
                            -- Create quest card (same as other plans)
                            local questCard = CreateCard(parent, questCardHeight)
                            questCard:SetWidth(questCardWidth)
                            questCard:EnableMouse(true)
                            
                            -- Add quest card to layout manager
                            CardLayoutManager:AddCard(layoutManager, questCard, questCol, questCardHeight)
                            
                            questCardIndex = questCardIndex + 1
                            
                            -- Apply green border for daily quests (added = green)
                            if ApplyVisuals then
                                ApplyVisuals(questCard, {0.08, 0.08, 0.10, 1}, {0.30, 0.90, 0.30, 0.8})
                            end
                            
                            -- NO hover effect on plan cards (as requested)
                            
                            -- Icon with border (using Factory pattern)
                            local iconBorder = ns.UI.Factory:CreateContainer(questCard, 46, 46)
                            iconBorder:SetPoint("TOPLEFT", 10, -10)
                            -- Icon border removed (naked frame)
                            -- Icon border removed (naked frame)
                            
                            local iconFrameObj = CreateIcon(questCard, nil, 42, false, nil, false)
                            iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
                            local iconFrame = iconFrameObj.texture
                            
                            if catData.atlas then
                                iconFrame:SetAtlas(catData.atlas)
                            elseif catData.texture then
                                iconFrame:SetTexture(catData.texture)
                            end
                            
                            -- Quest title (right of icon)
                            local questTitle = FontManager:CreateFontString(questCard, "body", "OVERLAY")
                            questTitle:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
                            questTitle:SetPoint("RIGHT", questCard, "RIGHT", -10, 0)
                            questTitle:SetText("|cffffffff" .. (quest.title or "Unknown Quest") .. "|r")
                            questTitle:SetJustifyH("LEFT")
                            questTitle:SetWordWrap(true)
                            questTitle:SetMaxLines(2)
                            
                            -- Quest type badge with icon (using Factory pattern)
                            local questIconFrame = ns.UI.Factory:CreateContainer(questCard)
                            questIconFrame:SetSize(20, 20)
                            questIconFrame:SetPoint("TOPLEFT", questTitle, "BOTTOMLEFT", 0, -2)
                            questIconFrame:EnableMouse(false)
                            
                            local questIconTexture = questIconFrame:CreateTexture(nil, "OVERLAY")
                            questIconTexture:SetAllPoints()
                            local questIconSuccess = pcall(function()
                                questIconTexture:SetAtlas("quest-legendary-turnin", false)
                            end)
                            if not questIconSuccess then
                                questIconFrame:Hide()
                            else
                                questIconTexture:SetSnapToPixelGrid(false)
                                questIconTexture:SetTexelSnappingBias(0)
                            end
                            
                            local questTypeBadge = FontManager:CreateFontString(questCard, "body", "OVERLAY")
                            if questIconSuccess then
                                questTypeBadge:SetPoint("LEFT", questIconFrame, "RIGHT", 4, 0)
                            else
                                questTypeBadge:SetPoint("TOPLEFT", questTitle, "BOTTOMLEFT", 0, -2)
                            end
                            questTypeBadge:SetText(string.format("|cff%02x%02x%02x%s|r", 
                                catData.color[1]*255, catData.color[2]*255, catData.color[3]*255,
                                catData.name))
                            questTypeBadge:EnableMouse(false)
                            
                            -- Description: "Zone: X - Daily Quest" format
                            local descY = -50
                            local descText = FontManager:CreateFontString(questCard, "small", "OVERLAY")
                            descText:SetPoint("TOPLEFT", 10, descY)
                            descText:SetPoint("RIGHT", questCard, "RIGHT", -10, 0)
                            
                            -- Build description
                            local descParts = {}
                            if quest.zone and quest.zone ~= "" then
                                table.insert(descParts, "Zone: " .. quest.zone)
                            end
                            table.insert(descParts, catData.name)
                            
                            descText:SetText("|cffaaaaaa" .. table.concat(descParts, " - ") .. "|r")
                            descText:SetJustifyH("LEFT")
                            descText:SetWordWrap(true)
                            descText:SetMaxLines(2)
                            
                            -- Time left (bottom left)
                            if quest.timeLeft and quest.timeLeft > 0 then
                                local days = math.floor(quest.timeLeft / 1440)
                                local hours = math.floor((quest.timeLeft % 1440) / 60)
                                local mins = quest.timeLeft % 60
                                
                                local timeStr
                                if days > 0 then
                                    timeStr = string.format("%dd %dh", days, hours)
                                elseif hours > 0 then
                                    timeStr = string.format("%dh %dm", hours, mins)
                                else
                                    timeStr = string.format("%dm", mins)
                                end
                                
                                local timeColor = hours < 1 and "|cffff8080" or "|cffffffff"
                                
                                local timeText = FontManager:CreateFontString(questCard, "body", "OVERLAY")
                                timeText:SetPoint("BOTTOMLEFT", 10, 6)
                                timeText:SetText("|TInterface\\COMMON\\UI-TimeIcon:16:16|t " .. timeColor .. timeStr .. "|r")
                            end
                            
                            questCard:Show()
                        end
                    end
                end
            end
            
            -- No incomplete quests message
            if not hasQuests then
                local noQuestsCard = CreateCard(parent, 60)
                noQuestsCard:EnableMouse(true)
                
                -- Add to layout manager as column 0 (for tracking), but will be full width
                local noQuestsYPos = CardLayoutManager:AddCard(layoutManager, noQuestsCard, 0, 60)
                
                -- Override positioning to make it full width
                noQuestsCard:ClearAllPoints()
                noQuestsCard:SetPoint("TOPLEFT", 10, -noQuestsYPos)
                noQuestsCard:SetPoint("TOPRIGHT", -10, -noQuestsYPos)
                
                local noQuestsText = FontManager:CreateFontString(noQuestsCard, "title", "OVERLAY")
                noQuestsText:SetPoint("CENTER")
                noQuestsText:SetTextColor(0.3, 1, 0.3)
                noQuestsText:SetText("All quests complete!")
                
                -- Update layout manager for full-width message card (update both columns to same Y)
                layoutManager.currentYOffsets[0] = noQuestsYPos + 60 + cardSpacing
                layoutManager.currentYOffsets[1] = noQuestsYPos + 60 + cardSpacing
                
                -- Mark card as full width for layout recalculation
                if noQuestsCard._layoutInfo then
                    noQuestsCard._layoutInfo.isFullWidth = true
                end
                
                noQuestsCard:Show()
            end
        
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
                -- For custom plans, add a complete button (green checkmark) before the X
                if plan.type == "custom" then
                    local completeBtn = ns.UI.Factory:CreateButton(card, 20, 20)
                    completeBtn:SetPoint("TOPRIGHT", -32, -8)  -- Left of the X button
                    completeBtn:SetNormalTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    completeBtn:SetHighlightTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    completeBtn:GetHighlightTexture():SetAlpha(0.5)
                    completeBtn:SetScript("OnClick", function()
                        if self.ToggleCustomPlanCompletion then
                            self:ToggleCustomPlanCompletion(plan.id)
                            if self.RefreshUI then self:RefreshUI() end
                        end
                    end)
                end
                
                local removeBtn = ns.UI.Factory:CreateButton(card, 20, 20)
                removeBtn:SetPoint("TOPRIGHT", -8, -8)
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
            end
            
            -- CRITICAL: Show the regular plan card!
            card:Show()
        end  -- End if card check
        end  -- End of regular plans (else block)
    end
    
    -- Get final Y offset from layout manager
    local finalYOffset = CardLayoutManager:GetFinalYOffset(layoutManager)
    
    return finalYOffset
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

--[[
    Handle WN_PLANS_UPDATED event
    Refreshes UI when plans are added, removed, or updated
]]
function WarbandNexus:OnPlansUpdated(event, data)
    if not data or not data.action then
        return
    end
    
    -- Refresh UI to show changes
    if self.RefreshUI then
        self:RefreshUI()
    end
end


-- ============================================================================
-- BROWSER (Mounts, Pets, Toys, Recipes)
-- ============================================================================

function WarbandNexus:DrawBrowser(parent, yOffset, width, category)
    
    --[[
        [DEPRECATED] CollectionScanner removed - now using CollectionService with DB-backed cache
        Scanning progress is handled by CreateLoadingIndicator in DrawBrowserResults
        This legacy progress banner code has been removed.
    ]]
    
    -- [REMOVED] Legacy CollectionScanner.IsReady() check (14 lines removed)
    -- CollectionService now uses persistent cache - no scanning delay needed
    
    if false then -- Keep structure for future reference, but disable execution
        local progressText = FontManager:CreateFontString(nil, "body", "OVERLAY")
        progressText:SetPoint("TOP", titleText, "BOTTOM", 0, -10)
        progressText:SetTextColor(1, 1, 1)  -- White
        local progressPercent = math.floor(progress.percent or 0)
        progressText:SetText(string.format("Progress: %d%%", progressPercent))
        
        local hintText = FontManager:CreateFontString(bannerCard, "small", "OVERLAY")
        hintText:SetPoint("TOP", progressText, "BOTTOM", 0, -10)
        hintText:SetTextColor(1, 1, 1)  -- White
        hintText:SetText("This only happens once after login. Results will be instant when ready!")
        
        bannerCard:Show()
        
        return yOffset + 120
    end
    
    -- Use SharedWidgets search bar (like Items tab)
    -- Create results container that can be refreshed independently
    local resultsContainer = CreateResultsContainer(parent, yOffset + 40, 10)
    
    -- Create unique search ID for this category (e.g., "plans_mount", "plans_pet")
    local searchId = "plans_" .. (category or "unknown"):lower()
    local initialSearchText = SearchStateManager:GetQuery(searchId)
    
    local searchContainer = CreateSearchBox(parent, width, "Search " .. category .. "s...", function(text)
        searchText = text
        browseResults = {}
        
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
    
    -- Get FRESH criteria count from API
    local freshNumCriteria = GetAchievementNumCriteria(achievement.id)
    
    -- Build Information section (always shown when expanded)
    local informationText = ""
    if achievement.description and achievement.description ~= "" then
        informationText = FormatTextNumbers(achievement.description)
    end
    
    -- Get achievement rewards (title, mount, pet, toy, transmog)
    local rewardInfo = WarbandNexus:GetAchievementRewardInfo(achievement.id)
    if rewardInfo then
        if informationText ~= "" then
            informationText = informationText .. "\n\n"
        end
        
        if rewardInfo.type == "title" then
            informationText = informationText .. "|cffffcc00Reward:|r Title - |cff00ff00" .. rewardInfo.title .. "|r"
        elseif rewardInfo.itemName then
            local itemTypeText = rewardInfo.type:gsub("^%l", string.upper) -- Capitalize
            informationText = informationText .. "|cffffcc00Reward:|r " .. itemTypeText .. " - |cff00ff00" .. rewardInfo.itemName .. "|r"
        end
    elseif achievement.rewardText and achievement.rewardText ~= "" then
        if informationText ~= "" then
            informationText = informationText .. "\n\n"
        end
        informationText = informationText .. "|cffffcc00Reward:|r " .. FormatTextNumbers(achievement.rewardText)
    end
    
    if informationText == "" then
        informationText = "|cffffffffNo additional information|r"
    end
    
    -- Build Requirements section
    local requirementsText = ""
    if freshNumCriteria and freshNumCriteria > 0 then
        local completedCount = 0
        local criteriaDetails = {}
        
        for criteriaIndex = 1, freshNumCriteria do
            local criteriaName, criteriaType, completed, quantity, reqQuantity, charName, flags, assetID, quantityString = GetAchievementCriteriaInfo(achievement.id, criteriaIndex)
            if criteriaName and criteriaName ~= "" then
                if completed then
                    completedCount = completedCount + 1
                end
                
                local statusIcon = completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t" or "|cffffffff•|r"
                local textColor = completed and "|cff44ff44" or "|cffffffff"  -- Green for completed, white for incomplete
                local progressText = ""
                
                if quantity and reqQuantity and reqQuantity > 0 then
                    -- Green progress for completed, white for incomplete
                    local progressColor = completed and "|cff44ff44" or "|cffffffff"
                    progressText = string.format(" %s(%s/%s)|r", progressColor, FormatNumber(quantity), FormatNumber(reqQuantity))
                end
                
                -- Format numbers in criteria name (e.g., "Kill 50000 enemies" -> "Kill 50.000 enemies")
                local formattedCriteriaName = FormatTextNumbers(criteriaName)
                table.insert(criteriaDetails, statusIcon .. " " .. textColor .. formattedCriteriaName .. "|r" .. progressText)
            end
        end
        
        if #criteriaDetails > 0 then
            local progressPercent = math.floor((completedCount / freshNumCriteria) * 100)
            local progressColor = (completedCount == freshNumCriteria) and "|cff00ff00" or "|cffffffff"
            requirementsText = string.format("%s%s of %s (%s%%)|r\n", progressColor, FormatNumber(completedCount), FormatNumber(freshNumCriteria), FormatNumber(progressPercent))
            requirementsText = requirementsText .. table.concat(criteriaDetails, "\n")
        else
            requirementsText = "|cffffffffNo criteria found|r"
        end
    else
        requirementsText = "|cffffffffNo requirements (instant completion)|r"
    end
    
    -- Prepare row data for CreateExpandableRow
    local rowData = {
        icon = achievement.icon,
        score = achievement.points,
        title = FormatTextNumbers(achievement.name),  -- Format numbers in title (e.g., "50000 Kills" -> "50.000 Kills")
        information = informationText,
        criteria = requirementsText
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
            -- Without this, expanded rows don't push other rows down
            WarbandNexus:RefreshUI()
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
    
    -- Add "+ Add" button or "Added" indicator (using Factory)
    local PlanCardFactory = ns.UI_PlanCardFactory
    
    if achievement.isPlanned then
        row.addedIndicator = PlanCardFactory.CreateAddedIndicator(row.headerFrame, {
            buttonType = "row",
            label = "Added",
            fontCategory = "body"
        })
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
                
                -- Hide button and show "Added" indicator
                btn:Hide()
                row.addedIndicator = PlanCardFactory.CreateAddedIndicator(row.headerFrame, {
                    buttonType = "row",
                    label = "Added",
                    fontCategory = "body"
                })
                
                -- Update achievement flag
                achievement.isPlanned = true
                
                -- Refresh UI (will update all other instances)
                WarbandNexus:RefreshUI()
            end
        })
    end
    
    -- Return new yOffset
    return yOffset + row:GetHeight() + 2
end

function WarbandNexus:DrawAchievementsTable(parent, results, yOffset, width, searchText)
    
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
            name = categoryName or "Unknown Category",
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
                self:RefreshUI()
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
            
            -- Draw root's own achievements first (if any)
            for i, achievement in ipairs(rootCategory.achievements) do
                animIdx = animIdx + 1
                yOffset = RenderAchievementRow(self, parent, achievement, yOffset, width, 0, animIdx, shouldAnimate, expandedGroups)
            end
            
            -- Draw child categories (sub-categories)
            for _, childID in ipairs(rootCategory.children) do
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
                        self:RefreshUI()
                    end,
                    "Interface\\Icons\\Achievement_General",
                    false
                )
                childHeader:SetPoint("TOPLEFT", GetLayout().BASE_INDENT, -yOffset) -- Standard indent
                childHeader:SetWidth(width - GetLayout().BASE_INDENT)
                
                yOffset = yOffset + GetLayout().HEADER_HEIGHT
                
                -- Draw sub-category content if expanded
                if childExpanded then
                    -- First, draw this category's own achievements
                    if #childCategory.achievements > 0 then
                        for i, achievement in ipairs(childCategory.achievements) do
                            animIdx = animIdx + 1
                            yOffset = RenderAchievementRow(self, parent, achievement, yOffset, width, GetLayout().BASE_INDENT, animIdx, shouldAnimate, expandedGroups)
                        end
                    end
                    
                    -- Now draw grandchildren categories (3rd level: e.g., Quests > Eastern Kingdoms > Zone)
                    for _, grandchildID in ipairs(childCategory.children or {}) do
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
                                    self:RefreshUI()
                                end,
                                "Interface\\Icons\\Achievement_General",
                                false
                            )
                            grandchildHeader:SetPoint("TOPLEFT", GetLayout().BASE_INDENT * 2, -yOffset) -- Double indent (30px)
                            grandchildHeader:SetWidth(width - (GetLayout().BASE_INDENT * 2))
                            
                            yOffset = yOffset + GetLayout().HEADER_HEIGHT
                            
                            -- Draw grandchild achievements if expanded
                            if grandchildExpanded then
                                for i, achievement in ipairs(grandchildCategory.achievements) do
                                    animIdx = animIdx + 1
                                    yOffset = RenderAchievementRow(self, parent, achievement, yOffset, width, GetLayout().BASE_INDENT * 2, animIdx, shouldAnimate, expandedGroups)
                                end
                            end
                        end
                    end
                    
                    -- Show "all completed" message only if no achievements in child AND no grandchildren
                    if #childCategory.achievements == 0 and #childCategory.children == 0 then
                        local noAchievementsText = FontManager:CreateFontString(parent, "body", "OVERLAY")
                        noAchievementsText:SetPoint("TOPLEFT", GetLayout().BASE_INDENT * 2, -yOffset)
                        noAchievementsText:SetText("|cff88cc88[COMPLETED] You already completed all achievements in this category!|r")
                        yOffset = yOffset + 25
                    end
                end
                end  -- if childAchievementCount > 0
            end
            
            -- Show "all completed" message only if root has no achievements AND no children
            if #rootCategory.achievements == 0 and #rootCategory.children == 0 then
                local noAchievementsText = FontManager:CreateFontString(parent, "body", "OVERLAY")
                noAchievementsText:SetPoint("TOPLEFT", GetLayout().BASE_INDENT, -yOffset)
                noAchievementsText:SetText("|cff88cc88[COMPLETED] You already completed all achievements in this category!|r")
                yOffset = yOffset + 25
            end
        end
        
        -- Spacing after category (WoW-like: compact)
        yOffset = yOffset + SECTION_SPACING + 4
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
    
    -- UNIFIED LOADING STATE: Show loading indicator if scan is in progress for THIS category
    -- Works for ALL collection types (mount, pet, toy, achievement, title, transmog, illusion)
    if categoryState.isLoading then
        local loadingStateData = {
            isLoading = true,
            loadingProgress = categoryState.loadingProgress or 0,
            currentStage = categoryState.currentStage or "Preparing...",
        }
        
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            -- Capitalize first letter for display
            local displayName = category:gsub("^%l", string.upper) .. "s"
            if category == "transmog" then displayName = "Transmog" end
            if category == "illusion" then displayName = "Illusions" end
            
            local newYOffset = UI_CreateLoadingStateCard(
                parent, 
                yOffset, 
                loadingStateData, 
                "Scanning " .. displayName
            )
            return newYOffset
        else
            print("|cffff0000[WN PlansUI]|r UI_CreateLoadingStateCard not found!")
            return yOffset + 120
        end
    end
    
    -- Get results based on category
    local results = {}
    if category == "mount" then
        results = self:GetUncollectedMounts(searchText, 50)
        print("|cff9370DB[WN PlansUI]|r DrawBrowserResults: Got " .. #results .. " mounts")
    elseif category == "pet" then
        results = self:GetUncollectedPets(searchText, 50)
        print("|cff9370DB[WN PlansUI]|r DrawBrowserResults: Got " .. #results .. " pets")
    elseif category == "toy" then
        results = self:GetUncollectedToys(searchText, 50)
        print("|cff9370DB[WN PlansUI]|r DrawBrowserResults: Got " .. #results .. " toys")
    elseif category == "transmog" then
        -- Transmog browser with sub-categories
        return self:DrawTransmogBrowser(parent, yOffset, width)
    elseif category == "illusion" then
        results = WarbandNexus:GetUncollectedIllusions(searchText, 50)
    elseif category == "title" then
        results = WarbandNexus:GetUncollectedTitles(searchText, 50)
    elseif category == "achievement" then
        results = WarbandNexus:GetUncollectedAchievements(searchText, 99999)
        
        -- Update isPlanned flags for achievements
        for _, item in ipairs(results) do
            item.isPlanned = self:IsAchievementPlanned(item.id)
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
        helpText:SetText("|cffffcc00Recipe Browser|r")
        
        local helpDesc = FontManager:CreateFontString(helpCard, "small", "OVERLAY")
        helpDesc:SetPoint("TOP", helpText, "BOTTOM", 0, -8)
        helpDesc:SetText("|cffffffffOpen your Profession window in-game to browse recipes.\nThe addon will scan available recipes when the window is open.|r")
        helpDesc:SetJustifyH("CENTER")
        helpDesc:SetWidth(width - 40)
        
        helpCard:Show()
        
        return yOffset + 100
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
        print("|cffffcc00[WN PlansUI WARNING]|r No results to display for category: " .. category)
        
        local noResultsCard = CreateCard(parent, 80)
        noResultsCard:SetPoint("TOPLEFT", 0, -yOffset)
        noResultsCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local noResultsText = FontManager:CreateFontString(noResultsCard, "title", "OVERLAY")
        noResultsText:SetPoint("CENTER", 0, 10)
        noResultsText:SetTextColor(1, 1, 1)  -- White
        noResultsText:SetText("No " .. category .. "s found")
        
        local noResultsDesc = FontManager:CreateFontString(noResultsCard, "body", "OVERLAY")
        noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
        noResultsDesc:SetTextColor(1, 1, 1)  -- White
        noResultsDesc:SetText("Try adjusting your search or filters.")
        
        noResultsCard:Show()
        
        return yOffset + 100
    end
    
    -- Sort results: Affordable first, then buyable, then others
    -- Sort alphabetically by name
    table.sort(results, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    
    -- Filter based on showCompleted flag
    if showCompleted then
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
            noResultsText:SetText("No collected " .. category .. "s yet")
            
            local noResultsDesc = FontManager:CreateFontString(noResultsCard, "body", "OVERLAY")
            noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
            noResultsDesc:SetTextColor(1, 1, 1)  -- White
            noResultsDesc:SetText("Start collecting to see them here!")
            
            noResultsCard:Show()
            
            return yOffset + 100
        end
    else
        -- Show ONLY uncollected items (default)
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
            noResultsText:SetText("All " .. category .. "s collected!")
            
            local noResultsDesc = FontManager:CreateFontString(noResultsCard, "body", "OVERLAY")
            noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
            noResultsDesc:SetTextColor(1, 1, 1)  -- White
            noResultsDesc:SetText("You've collected everything in this category!")
            
            noResultsCard:Show()
            
            return yOffset + 100
        end
    end
    
    -- === 2-COLUMN CARD GRID (Fixed height, clean layout) ===
    local cardSpacing = 8
    local cardWidth = (width - cardSpacing) / 2  -- 2 columns with spacing to match title bar width
    local cardHeight = 130  -- Increased for better readability
    local col = 0
    
    for i, item in ipairs(results) do
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
        
        -- NO hover effect on plan cards (as requested)
        
        -- Icon (large) with border
        local iconBorder = ns.UI.Factory:CreateContainer(card, 46, 46)
        iconBorder:SetPoint("TOPLEFT", 10, -10)
        -- Icon border removed (naked frame)
        
        local iconFrameObj = CreateIcon(card, item.icon or "Interface\\Icons\\INV_Misc_QuestionMark", 42, false, nil, false)
        if iconFrameObj then
            iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
            iconFrameObj:Show()  -- CRITICAL: Show the icon!
        end
        -- TexCoord already applied by CreateIcon factory
        
        -- === TITLE ===
        local nameText = FontManager:CreateFontString(card, "body", "OVERLAY")
        nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
        nameText:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        nameText:SetText("|cffffffff" .. FormatTextNumbers(item.name or "Unknown") .. "|r")
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
            pointsText:SetText(string.format("|cff%02x%02x%02x%s Points|r", 
                255*255, 204*255, 51*255,  -- Gold color
                FormatNumber(item.points)))
            pointsText:EnableMouse(false)  -- Allow clicks to pass through
        else
            -- Other types: Show type badge with icon (like in My Plans)
            local typeNames = {
                mount = "Mount",
                pet = "Pet",
                toy = "Toy",
                recipe = "Recipe",
                illusion = "Illusion",
                title = "Title",
                transmog = "Transmog",
            }
            local typeName = typeNames[category] or "Unknown"
            
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
            achievementText:SetText("|TInterface\\Icons\\Achievement_General:16:16|t Source: |cff00ff00[Achievement " .. item.sourceAchievement .. "]|r")
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
                    
                    print("|cff00ff00[WN PlansUI]|r Jumping to achievement: " .. item.sourceAchievement)
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
            vendorText:SetText("|A:Class:16:16|a Vendor: " .. firstSource.vendor)
            vendorText:SetTextColor(1, 1, 1)
            vendorText:SetJustifyH("LEFT")
            vendorText:SetWordWrap(true)
            vendorText:SetMaxLines(2)
            vendorText:SetNonSpaceWrap(false)
        elseif firstSource.npc then
            local npcText = FontManager:CreateFontString(card, "body", "OVERLAY")
            npcText:SetPoint("TOPLEFT", 10, line3Y)
            npcText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            npcText:SetText("|A:Class:16:16|a Drop: " .. firstSource.npc)
            npcText:SetTextColor(1, 1, 1)
            npcText:SetJustifyH("LEFT")
            npcText:SetWordWrap(true)
            npcText:SetMaxLines(2)
            npcText:SetNonSpaceWrap(false)
        elseif firstSource.faction then
            local factionText = FontManager:CreateFontString(card, "body", "OVERLAY")
            factionText:SetPoint("TOPLEFT", 10, line3Y)
            factionText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            local displayText = "|A:Class:16:16|a Faction: " .. firstSource.faction
            if firstSource.renown then
                local repType = firstSource.isFriendship and "Friendship" or "Renown"
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
            zoneText:SetText("|A:Class:16:16|a Zone: " .. firstSource.zone)
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
                    infoText:SetText("|cff88ff88Information:|r |cffffffff" .. description .. "|r")
                    infoText:SetJustifyH("LEFT")
                    infoText:SetWordWrap(true)
                    infoText:SetMaxLines(2)
                    infoText:SetNonSpaceWrap(false)
                    lastElement = infoText
                elseif item.description and item.description ~= "" then
                    local infoText = FontManager:CreateFontString(card, "body", "OVERLAY")
                    infoText:SetPoint("TOPLEFT", 10, line3Y)
                    infoText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    infoText:SetText("|cff88ff88Information:|r |cffffffff" .. FormatTextNumbers(item.description) .. "|r")
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
                    progressText:SetText("|cffffcc00Progress:|r |cffffffff" .. progress:gsub("Progress:%s*", "") .. "|r")
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
                    rewardText:SetText("|cff88ff88Reward:|r |cffffffff" .. item.rewardText .. "|r")
                    rewardText:SetJustifyH("LEFT")
                    rewardText:SetWordWrap(true)
                    rewardText:SetMaxLines(2)
                    rewardText:SetNonSpaceWrap(false)
                end
            else
                -- Regular source text handling for mounts/pets/toys/illusions
                -- Skip source display for titles (they just show the title name)
                if category ~= "title" then
                    local sourceText = FontManager:CreateFontString(card, "body", "OVERLAY")
                    sourceText:SetPoint("TOPLEFT", 10, line3Y)
                    sourceText:SetPoint("RIGHT", card, "RIGHT", -80, 0)  -- Leave space for + Add button
                    
                    local rawText = item.source or ""
                    if WarbandNexus.CleanSourceText then
                        rawText = WarbandNexus:CleanSourceText(rawText)
                    end
                    -- Replace newlines with spaces and collapse whitespace
                    rawText = rawText:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                    
                    -- If no valid source text, show default message
                    if rawText == "" or rawText == "Unknown" then
                        rawText = "Unknown source"
                    end
                    
                    -- Check if text already has a source type prefix (Vendor:, Drop:, Discovery:, Garrison Building:, etc.)
                    -- Pattern matches any text ending with ":" at the start (including multi-word like "Garrison Building:")
                    local sourceType, sourceDetail = rawText:match("^([^:]+:%s*)(.*)$")
                    
                    -- Only add "Source:" label if text doesn't already have a source type prefix
                    if sourceType and sourceDetail and sourceDetail ~= "" then
                        -- Text already has source type (e.g., "Discovery: Zul'Gurub" or "Garrison Building: Gladiator's Sanctum")
                        -- Color the source type prefix to match other field labels
                        -- Determine icon based on source type
                        local iconAtlas = "|A:Class:16:16|a "  -- Default icon (Class for all sources)
                        local lowerType = string.lower(sourceType)
                        if lowerType:match("profession") or lowerType:match("crafted") then
                            iconAtlas = "|A:Repair:16:16|a "  -- Repair for Profession
                        end
                        -- All other source types use Class icon
                        sourceText:SetText(iconAtlas .. "|cff99ccff" .. sourceType .. "|r|cffffffff" .. sourceDetail .. "|r")
                    else
                        -- No source type prefix, add "Source:" label
                        sourceText:SetText("|A:Class:16:16|a |cff99ccffSource:|r |cffffffff" .. rawText .. "|r")
                    end
                    
                    sourceText:SetJustifyH("LEFT")
                    sourceText:SetWordWrap(true)
                    sourceText:SetMaxLines(2)  -- 2 lines for non-achievements
                    sourceText:SetNonSpaceWrap(false)  -- Break at spaces only
                end
            end
        end
        
        -- Add/Added button (bottom right) using Factory
        local PlanCardFactory = ns.UI_PlanCardFactory
        
        if item.isPlanned then
            PlanCardFactory.CreateAddedIndicator(card, {
                buttonType = "card",
                label = "Added",
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
                    
                    -- Update card border to green immediately (added state)
                    if UpdateBorderColor then
                        UpdateBorderColor(card, {0.30, 0.90, 0.30, 0.8})
                    end
                    
                    -- Hide the Add button and show Added indicator (self is the button)
                    self:Hide()
                    PlanCardFactory.CreateAddedIndicator(card, {
                        buttonType = "card",
                        label = "Added",
                        fontCategory = "body"
                    })
                end
            })
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
        title = "Create Custom Plan",
        icon = "Bonus-Objective-Star",  -- Use atlas for custom plans
        iconIsAtlas = true,
        width = 450,
        height = 380,  -- Increased height for better spacing
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
    titleLabel:SetText("|cff" .. string.format("%02x%02x%02x", COLORS.accent[1]*255, COLORS.accent[2]*255, COLORS.accent[3]*255) .. "Title:|r")
    
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
    descLabel:SetText("|cff" .. string.format("%02x%02x%02x", COLORS.accent[1]*255, COLORS.accent[2]*255, COLORS.accent[3]*255) .. "Description:|r")
    
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
    
    -- Buttons (symmetrically centered with more spacing from inputs)
    local saveBtn = CreateThemedButton(contentFrame, "Save", 100)
    saveBtn:SetPoint("BOTTOM", -55, 12)
    saveBtn:SetScript("OnClick", function()
        local title = titleInput:GetText()
        local description = descInput:GetText()
        
        if title and title ~= "" then
            WarbandNexus:SaveCustomPlan(title, description)
            dialog.Close()
            if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
        end
    end)
    
    local cancelBtn = CreateThemedButton(contentFrame, "Cancel", 100)
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

function WarbandNexus:SaveCustomPlan(title, description)
    if not self.db.global.customPlans then
        self.db.global.customPlans = {}
    end
    
    local customPlan = {
        id = "custom_" .. time() .. "_" .. math.random(1000, 9999),
        type = "custom",
        name = title,
        source = description or "Custom plan",
        icon = "Bonus-Objective-Star",  -- Use atlas for custom plans
        iconIsAtlas = true,  -- Mark as atlas
        isCustom = true,
        completed = false,
    }
    
    table.insert(self.db.global.customPlans, customPlan)
end

function WarbandNexus:GetCustomPlans()
    return self.db.global.customPlans or {}
end

function WarbandNexus:ToggleCustomPlanCompletion(planId)
    if not self.db.global.customPlans then return end
    
    for _, plan in ipairs(self.db.global.customPlans) do
        if plan.id == planId then
            plan.completed = not (plan.completed or false)
            local status = plan.completed and "|cff00ff00completed|r" or "|cffffffffmarked as incomplete|r"
            self:Print("Custom plan '" .. FormatTextNumbers(plan.name) .. "' " .. status)
            
            -- Show notification if completed
            if plan.completed and self.ShowToastNotification then
                self:ShowToastNotification({
                    icon = plan.icon or "Interface\\Icons\\INV_Misc_Note_01",
                    title = "Plan Completed!",
                    subtitle = "Custom Goal Achieved",
                    message = FormatTextNumbers(plan.name),
                    category = "CUSTOM",
                    planType = "custom",
                    autoDismiss = 8,
                    playSound = true,
                })
            end
            
            return plan.completed
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
        title = "Weekly Vault Tracker",
        icon = "Interface\\Icons\\INV_Misc_Note_06",  -- Same as Daily Quest
        width = 500,
        height = existingPlan and 260 or 470  -- Optimized spacing
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
        warningText:SetText("|cffff9900Weekly Plan Already Exists|r")
        
        local infoText = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        infoText:SetPoint("TOP", warningText, "BOTTOM", 0, -10)
        infoText:SetWidth(440)
        infoText:SetWordWrap(true)
        infoText:SetJustifyH("CENTER")
        infoText:SetText("|cffaaaaaa" .. currentName .. "-" .. currentRealm .. " already has an active weekly vault plan. You can find it in the 'My Plans' category.|r")
        
        -- Calculate text height to position button below
        local textHeight = infoText:GetStringHeight()
        
        -- OK button (positioned below text)
        local okBtn = CreateThemedButton(contentFrame, "OK", 120)
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
            progressHeader:SetText("Current Progress")
            
            -- 3-column progress display (centered) - PREMIUM DASHBOARD
            local colWidth = 145
            local colSpacing = 12
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
                local starSpacing = 42
                local starSize = 24  -- Bigger stars
                local starTotalWidth = (3 - 1) * starSpacing
                local starStartX = -starTotalWidth / 2
                
                for i = 1, 3 do
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
                    milestoneText:SetText(string.format("%s/%s", FormatNumber(math.min(current, thresholds[i])), FormatNumber(thresholds[i])))
                end
            end
            
            -- Dungeons (column 1)
            CreateProgressCol(
                1,
                "questlog-questtypeicon-heroic",
                "Mythic+",
                progress.dungeonCount,
                {1, 4, 8}  -- Thresholds
            )
            
            -- Raids (column 2)
            CreateProgressCol(
                2,
                "questlog-questtypeicon-raid",
                "Raids",
                progress.raidBossCount,
                {2, 4, 6}  -- Thresholds
            )
            
            -- World (column 3)
            CreateProgressCol(
                3,
                "questlog-questtypeicon-Delves",
                "World",
                progress.worldActivityCount,
                {2, 4, 8}  -- Thresholds
            )
            
            contentY = contentY - 95  -- Increased from 70 to accommodate taller columns
        end
        
        -- Buttons (symmetrically centered)
        local createBtn = CreateThemedButton(contentFrame, "Create Plan", 120)
        createBtn:SetPoint("BOTTOM", -65, 8)
        createBtn:SetScript("OnClick", function()
            -- Create the weekly plan
            local plan = self:CreateWeeklyPlan(currentName, currentRealm)
            if plan then
                -- Refresh UI to show new plan
                if self.RefreshUI then
                    self:RefreshUI()
                end
                
                -- Close dialog
                dialog.Close()
            end
        end)
        
        local cancelBtn = CreateThemedButton(contentFrame, "Cancel", 120)
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
    
    -- Character info
    local currentName = UnitName("player")
    local currentRealm = GetRealmName()
    local _, currentClass = UnitClass("player")
    local classColors = RAID_CLASS_COLORS[currentClass]
    
    -- Check for existing plan
    local existingPlan = self:HasActiveDailyPlan(currentName, currentRealm)
    
    -- Create external window using helper
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "DailyPlanDialog",
        title = "Daily Quest Tracker",
        icon = "Interface\\Icons\\INV_Misc_Note_06",
        width = 500,
        height = existingPlan and 260 or 520
    })
    
    -- If dialog creation failed (duplicate), return
    if not dialog then
        return
    end
    
    if existingPlan then
        local contentY = -35
        -- Warning icon
        local warningIconFrame2 = CreateIcon(contentFrame, "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew", 48, false, nil, true)
        warningIconFrame2:SetPoint("TOP", 0, contentY)
        warningIconFrame2:Show()
        local warningIcon = warningIconFrame2.texture
        
        local warningText = FontManager:CreateFontString(contentFrame, "title", "OVERLAY")
        warningText:SetPoint("TOP", warningIcon, "BOTTOM", 0, -10)
        warningText:SetText("|cffff9900Daily Plan Already Exists|r")
        
        local infoText = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        infoText:SetPoint("TOP", warningText, "BOTTOM", 0, -10)
        infoText:SetWidth(440)
        infoText:SetWordWrap(true)
        infoText:SetJustifyH("CENTER")
        infoText:SetText("|cffaaaaaa" .. currentName .. "-" .. currentRealm .. " already has an active daily quest plan. You can find it in the 'Daily Tasks' category.|r")
        
        -- OK button
        local okBtn = CreateThemedButton(contentFrame, "OK", 120)
        okBtn:SetPoint("TOP", infoText, "BOTTOM", 0, -20)
        okBtn:SetScript("OnClick", function()
            dialog.Close()
        end)
        
        dialog:Show()
        return
    end
    
    -- State variables
    local selectedContent = "tww"
    local selectedQuestTypes = {
        dailyQuests = true,
        worldQuests = true,
        weeklyQuests = true,
        assignments = false
    }
    
    -- Character display with icon and border (using Factory pattern)
    local charFrame = ns.UI.Factory:CreateContainer(contentFrame, 460, 45)
    charFrame:SetPoint("TOP", 0, -15)
    
    -- Get race-gender info
    local _, englishRace = UnitRace("player")
    local gender = UnitSex("player") -- 2 = male, 3 = female
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
    
    -- Content selection
    local contentY = -75
    local contentLabel = FontManager:CreateFontString(contentFrame, "title", "OVERLAY", "accent")
    contentLabel:SetPoint("TOPLEFT", 12, contentY)
    contentLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    contentLabel:SetText("Select Content:")
    
    local contentOptions = {
        { key = "midnight", name = "Midnight", atlas = "majorfactions_icons_shadowstepcadre512", useAtlas = true },
        { key = "tww", name = "The War Within", atlas = "warwithin-landingbutton-down", useAtlas = true }
    }
    
    local contentButtons = {}
    local contentBtnY = contentY - 40
    
    for i, content in ipairs(contentOptions) do
        local btn = ns.UI.Factory:CreateButton(contentFrame, 180, 50)
        btn:SetPoint("TOPLEFT", 12, contentBtnY - (i-1) * 60)
        
        -- Apply border to content selection buttons
        if ApplyVisuals then
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
        
        btn.key = content.key
        contentButtons[content.key] = btn
        
        -- Icon (supports both atlas and texture)
        local iconFrame3
        if content.useAtlas then
            iconFrame3 = CreateIcon(btn, content.atlas, 32, true, nil, true)
        else
            iconFrame3 = CreateIcon(btn, content.icon, 32, false, nil, true)
        end
        iconFrame3:SetPoint("LEFT", 10, 0)
        
        -- Name
        local nameText = FontManager:CreateFontString(btn, "body", "OVERLAY")
        nameText:SetPoint("LEFT", iconFrame3, "RIGHT", 10, 0)
        nameText:SetText(FormatTextNumbers(content.name))
        
        btn:SetScript("OnClick", function()
            selectedContent = content.key
            
            -- Update all content buttons border colors
            for key, button in pairs(contentButtons) do
                if UpdateBorderColor then
                    if key == selectedContent then
                        -- Selected: Full accent color
                        UpdateBorderColor(button, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
                        if button.SetBackdropColor then
                            button:SetBackdropColor(COLORS.accent[1] * 0.3, COLORS.accent[2] * 0.3, COLORS.accent[3] * 0.3, 1)
                        end
                    else
                        -- Not selected: Dimmed
                        UpdateBorderColor(button, {COLORS.accent[1] * 0.6, COLORS.accent[2] * 0.6, COLORS.accent[3] * 0.6, 1})
                        if button.SetBackdropColor then
                            button:SetBackdropColor(0.12, 0.12, 0.15, 1)
                        end
                    end
                end
            end
        end)
    end
    
    -- Set initial content button state (tww is default)
    if UpdateBorderColor then
        for key, button in pairs(contentButtons) do
            if key == selectedContent then
                -- Selected: Full accent color
                UpdateBorderColor(button, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
                if button.SetBackdropColor then
                    button:SetBackdropColor(COLORS.accent[1] * 0.3, COLORS.accent[2] * 0.3, COLORS.accent[3] * 0.3, 1)
                end
            else
                -- Not selected: Dimmed
                UpdateBorderColor(button, {COLORS.accent[1] * 0.6, COLORS.accent[2] * 0.6, COLORS.accent[3] * 0.6, 1})
                if button.SetBackdropColor then
                    button:SetBackdropColor(0.12, 0.12, 0.15, 1)
                end
            end
        end
    end
    
    -- Quest type selection
    local questTypeY = contentY - 40
    local questTypeLabel = FontManager:CreateFontString(contentFrame, "title", "OVERLAY", "accent")
    questTypeLabel:SetPoint("TOPLEFT", 220, contentY)
    questTypeLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    questTypeLabel:SetText("Quest Types:")
    
    local questTypes = {
        { key = "dailyQuests", name = "Daily Quests", desc = "Regular daily quests from NPCs" },
        { key = "worldQuests", name = "World Quests", desc = "Zone-wide world quests" },
        { key = "weeklyQuests", name = "Weekly Quests", desc = "Weekly recurring quests" },
        { key = "assignments", name = "Assignments", desc = "Special assignments and tasks" }
    }
    
    for i, questType in ipairs(questTypes) do
        local cb = CreateThemedCheckbox(contentFrame, selectedQuestTypes[questType.key])
        cb:SetPoint("TOPLEFT", 220, questTypeY - (i-1) * 50)
        
        local label = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        label:SetPoint("LEFT", cb, "RIGHT", 8, 5)  -- Moved up 5 pixels
        label:SetText(questType.name)
        
        local desc = FontManager:CreateFontString(contentFrame, "small", "OVERLAY")
        desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        desc:SetTextColor(0.7, 0.7, 0.7)  -- Softer gray
        desc:SetText(questType.desc)
        
        -- Store reference and update handler
        cb:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            selectedQuestTypes[questType.key] = isChecked
            
            -- Update visual state explicitly
            if isChecked then
                if self.checkTexture then self.checkTexture:Show() end
            else
                if self.checkTexture then self.checkTexture:Hide() end
            end
        end)
    end
    
    -- Buttons (symmetrically centered)
    local createBtn = CreateThemedButton(contentFrame, "Create Plan", 120)
    createBtn:SetPoint("BOTTOM", -65, 8)
    createBtn:SetScript("OnClick", function()
        local plan = self:CreateDailyPlan(currentName, currentRealm, selectedContent, selectedQuestTypes)
        if plan then
            if self.RefreshUI then
                self:RefreshUI()
            end
            dialog.Close()
        end
    end)
    
    local cancelBtn = CreateThemedButton(contentFrame, "Cancel", 120)
    cancelBtn:SetPoint("BOTTOM", 65, 8)
    cancelBtn:SetScript("OnClick", function()
        dialog.Close()
    end)
    
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
    
    -- Work in Progress screen
    local wipCard = CreateCard(parent, 200)
    wipCard:SetPoint("TOPLEFT", 0, -yOffset)
    wipCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local wipIconFrame2 = CreateIcon(wipCard, "Interface\\Icons\\INV_Misc_EngGizmos_20", 64, false, nil, true)
    wipIconFrame2:SetPoint("TOP", 0, -30)
    local wipIcon = wipIconFrame2.texture
    
    local wipTitle = FontManager:CreateFontString(wipCard, "header", "OVERLAY", "accent")
    wipTitle:SetPoint("TOP", wipIcon, "BOTTOM", 0, -20)
    wipTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    wipTitle:SetText("Work in Progress")
    
    local wipDesc = FontManager:CreateFontString(wipCard, "body", "OVERLAY")
    wipDesc:SetPoint("TOP", wipTitle, "BOTTOM", 0, -15)
    wipDesc:SetWidth(width - 100)
    wipDesc:SetTextColor(1, 1, 1)  -- White
    wipDesc:SetJustifyH("CENTER")
    wipDesc:SetText("Transmog collection tracking is currently under development.\n\nThis feature will be available in a future update with improved\nperformance and better integration with Warband systems.")
    
    -- CRITICAL: Show the card and icon!
    wipCard:Show()
    wipIconFrame2:Show()
    
    return yOffset + 230
end

