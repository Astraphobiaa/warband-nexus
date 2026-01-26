--[[
    Warband Nexus - Plans Tab UI
    User-driven goal tracker for mounts, pets, and toys
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local function GetCOLORS()
    return ns.UI_COLORS
end
local CreateCard = ns.UI_CreateCard
local CreateSearchBox = ns.UI_CreateSearchBox
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateResultsContainer = ns.UI_CreateResultsContainer
local CreateIcon = ns.UI_CreateIcon
local ApplyVisuals = ns.UI_ApplyVisuals
local ApplyHoverEffect = ns.UI_ApplyHoverEffect
local UpdateBorderColor = ns.UI_UpdateBorderColor
local CreateExternalWindow = ns.UI_CreateExternalWindow
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local CreateTableRow = ns.UI_CreateTableRow
local CreateExpandableRow = ns.UI_CreateExpandableRow
local CreateCategorySection = ns.UI_CreateCategorySection
local CardLayoutManager = ns.UI_CardLayoutManager
local PlanCardFactory = ns.UI_PlanCardFactory

-- Import shared UI layout constants
local UI_LAYOUT = ns.UI_LAYOUT
local ROW_HEIGHT = UI_LAYOUT.rowHeight or 26
local ROW_SPACING = UI_LAYOUT.rowSpacing or 28
local HEADER_SPACING = UI_LAYOUT.headerSpacing or 40
local SECTION_SPACING = UI_LAYOUT.betweenSections or 8
local BASE_INDENT = UI_LAYOUT.BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = UI_LAYOUT.SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = UI_LAYOUT.SIDE_MARGIN or 10
local TOP_MARGIN = UI_LAYOUT.TOP_MARGIN or 8
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING or 40
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING or 8
local SIDE_MARGIN = UI_LAYOUT.sideMargin or 10
local TOP_MARGIN = UI_LAYOUT.topMargin or 8

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
    local yOffset = 8
    local width = parent:GetWidth() - 20
    local COLORS = GetCOLORS()
    
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
    
    -- Enable Module Checkbox
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.plans ~= false
    local enableCheckbox = CreateThemedCheckbox(titleCard, moduleEnabled)
    enableCheckbox:SetPoint("LEFT", headerIcon.border, "RIGHT", 8, 0)
    
    enableCheckbox:SetScript("OnClick", function(checkbox)
        local enabled = checkbox:GetChecked()
        -- Use ModuleManager for proper event handling
        if self.SetPlansModuleEnabled then
            self:SetPlansModuleEnabled(enabled)
        else
            -- Fallback
            self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
            self.db.profile.modulesEnabled.plans = enabled
            
            -- Start CollectionScanner when enabled
            if enabled then
                if self.CollectionScanner and self.CollectionScanner.Initialize then
                    if not self.CollectionScanner:IsReady() then
                        self.CollectionScanner:Initialize()
                    end
                end
            end
            
            if self.RefreshUI then self:RefreshUI() end
        end
    end)
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", enableCheckbox, "RIGHT", 12, 5)
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Collection Plans|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", enableCheckbox, "RIGHT", 12, -12)
    subtitleText:SetTextColor(1, 1, 1)  -- White
    
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
    
    subtitleText:SetText("Track your collection goals • " .. activePlanCount .. " active plan" .. (activePlanCount ~= 1 and "s" or ""))
    
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
        local checkboxLabel = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    
    yOffset = yOffset + UI_LAYOUT.afterHeader  -- Standard spacing after title card
    
    -- Check if module is disabled
    if not self.db.profile.modulesEnabled or self.db.profile.modulesEnabled.plans == false then
        local DrawEmptyState = ns.UI_DrawEmptyState
        DrawEmptyState(self, parent, yOffset, false, "")
        return yOffset + 100  -- Return a valid height value
    end
    
    -- Register event listener for plan updates (only once)
    if not self._plansEventRegistered then
        if self.RegisterMessage then
            self:RegisterMessage("WN_PLANS_UPDATED", "OnPlansUpdated")
        end
        self._plansEventRegistered = true
    end
    
    -- ===== CATEGORY BUTTONS (Responsive tabs with wrapping) =====
    local categoryBar = CreateFrame("Frame", nil, parent)
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
        
        local btn = CreateFrame("Button", nil, categoryBar)
        btn:SetSize(catBtnWidth, catBtnHeight)
        btn:SetPoint("TOPLEFT", currentX, -(currentRow * (catBtnHeight + catBtnSpacing)))
        
        -- Check if this is the active category
        local isActive = (cat.key == currentCategory)
        
        -- Apply border and background
        if ApplyVisuals then
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
        
        -- Apply hover effect
        if ApplyHoverEffect then
            ApplyHoverEffect(btn, 0.25)
        end
        
        -- Use atlas icon if available, otherwise use regular icon path
        local iconFrame
        if cat.iconAtlas then
            -- Create frame for atlas icon
            iconFrame = CreateFrame("Frame", nil, btn)
            iconFrame:SetSize(28, 28)
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
            end
        end
        
        -- Fallback to regular icon if atlas failed or not available
        if not iconFrame and cat.icon then
            iconFrame = CreateIcon(btn, cat.icon, 28, false, nil, true)
            iconFrame:SetPoint("LEFT", 10, 0)
        end
        
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
            if self.RefreshUI then self:RefreshUI() end
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
    local COLORS = GetCOLORS()
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
        
        -- Title
        local title = emptyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", iconFrame, "BOTTOM", 0, -15)
        title:SetText("|cff888888No planned activity|r")
        
        -- Description
        local desc = emptyCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        desc:SetPoint("TOP", title, "BOTTOM", 0, -10)
        desc:SetTextColor(0.7, 0.7, 0.7)
        desc:SetText("Click on Mounts, Pets, or Toys above to browse and add goals!")
        
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
        
        -- === WEEKLY VAULT PLANS (Full Width Card) - 3 SLOTS WITH PROGRESS BARS ===
        if plan.type == "weekly_vault" then
            local weeklyCardHeight = 170  -- Properly calculated height
            local card = CreateCard(parent, weeklyCardHeight)
            card:EnableMouse(true)
            
            -- Add to layout manager as column 0 (for tracking), but will be full width
            local yPos = CardLayoutManager:AddCard(layoutManager, card, 0, weeklyCardHeight)
            
            -- Override positioning to make it full width
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 10, -yPos)
            card:SetPoint("TOPRIGHT", -10, -yPos)
            
            -- Update layout manager for full-width card (update both columns to same Y)
            layoutManager.currentYOffsets[0] = yPos + weeklyCardHeight + cardSpacing
            layoutManager.currentYOffsets[1] = yPos + weeklyCardHeight + cardSpacing
            
            -- Mark card as full width for layout recalculation
            if card._layoutInfo then
                card._layoutInfo.isFullWidth = true
            end
            
            -- Apply green border for weekly vault plans (added = green)
            if ApplyVisuals then
                local borderColor = {0.30, 0.90, 0.30, 0.8}
                ApplyVisuals(card, {0.08, 0.08, 0.10, 1}, borderColor)
            end
            
            -- NO hover effect on plan cards (as requested)
            
            -- Get character class color
            local classColor = {1, 1, 1}
            if plan.characterClass then
                local classColors = RAID_CLASS_COLORS[plan.characterClass]
                if classColors then
                    classColor = {classColors.r, classColors.g, classColors.b}
                end
            end
            
            -- === HEADER WITH ICON (same style as regular plans) ===
            -- Icon with border
            local iconBorder = CreateFrame("Frame", nil, card)
            iconBorder:SetSize(46, 46)
            iconBorder:SetPoint("TOPLEFT", 10, -10)
            -- Icon border removed (naked frame)
            -- Icon border styling removed (naked frame)
            
            local iconFrameObj = CreateIcon(card, "greatVault-whole-normal", 42, true, nil, false)
            iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
            
            -- Title (right of icon)
            local titleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
            titleText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
            if plan.fullyCompleted then
                titleText:SetTextColor(0.2, 1, 0.2)  -- Green text
                titleText:SetText("Weekly Vault Plan - Complete")
            else
            titleText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
                titleText:SetText("Weekly Vault Plan")
            end
            titleText:SetJustifyH("LEFT")
            titleText:SetWordWrap(false)
            
            -- Character name (below title) - LARGER FONT
            local charText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            charText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
            charText:SetTextColor(classColor[1], classColor[2], classColor[3])
            charText:SetText(plan.characterName)
            
            -- Reset timer (right side, smaller font)
            local resetTime = self:GetWeeklyResetTime()
            local resetText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            resetText:SetPoint("TOPRIGHT", -26, -12)
            resetText:SetTextColor(1, 1, 1)  -- White
            resetText:SetText("Resets in " .. self:FormatTimeUntilReset(resetTime))
            
            -- Delete button (same as other plan cards)
            local removeBtn = CreateFrame("Button", nil, card)
            removeBtn:SetSize(20, 20)
            removeBtn:SetPoint("TOPRIGHT", -8, -8)
            removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
            removeBtn:SetScript("OnClick", function()
                self:RemovePlan(plan.id)
                if self.RefreshUI then
                    self:RefreshUI()
                end
            end)
            
            -- === 3 SLOTS (Mini Cards with Progress Bars) ===
            -- Get real-time progress from API
            local currentProgress = self:GetWeeklyVaultProgress(plan.characterName, plan.characterRealm) or {
                dungeonCount = 0,
                raidBossCount = 0,
                worldActivityCount = 0
            }
            
            -- Align slots starting from icon left edge
            local iconTopPadding = 10  -- Icon has 10px from top
            local iconLeftX = 10  -- Icon starts at 10px from left
            local contentY = -70  -- More space below header
            local cardWidth = card:GetWidth()
            local availableWidth = cardWidth - iconLeftX - 15  -- From icon to right edge with 15px padding
            local slotSpacing = 10
            local slotWidth = (availableWidth - slotSpacing * 2) / 3
            local slotHeight = 92  -- Taller to fit content with proper padding
            
            local slots = {
                {
                    atlas = "questlog-questtypeicon-heroic",
                    title = "Mythic+",
                    current = currentProgress.dungeonCount,
                    max = 8,
                    slotData = plan.slots.dungeon,
                    thresholds = {1, 4, 8}
                },
                {
                    atlas = "questlog-questtypeicon-raid",
                    title = "Raids",
                    current = currentProgress.raidBossCount,
                    max = 6,
                    slotData = plan.slots.raid,
                    thresholds = {2, 4, 6}
                },
                {
                    atlas = "questlog-questtypeicon-Delves",
                    title = "World",
                    current = currentProgress.worldActivityCount,
                    max = 8,
                    slotData = plan.slots.world,
                    thresholds = {2, 4, 8}
                }
            }
            
            for slotIndex, slot in ipairs(slots) do
                local slotX = iconLeftX + (slotIndex - 1) * (slotWidth + slotSpacing)  -- Aligned with icon
                
                -- Slot frame (mini card, no border)
                local slotFrame = CreateFrame("Frame", nil, card)
                slotFrame:SetSize(slotWidth, slotHeight)
                slotFrame:SetPoint("TOPLEFT", slotX, contentY)
                
                -- Icon + Title - moved up 10px more
                local slotTopPadding = iconTopPadding - 13  -- 10px higher than before
                local iconFrame = CreateIcon(slotFrame, slot.atlas, 28, true, nil, false)
                -- World icon: shift 2px to the right
                local iconXOffset = (slot.title == "World") and -34 or -36
                iconFrame:SetPoint("TOP", slotFrame, "TOP", iconXOffset, -(slotTopPadding + 14))
                
                local title = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                title:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
                title:SetText(slot.title)
                title:SetTextColor(0.95, 0.95, 0.95)
                
                -- Progress Bar (below icon+title, centered with equal padding)
                local barY = -52
                local barPadding = 18
                local barWidth = slotWidth - (barPadding * 2)
                local barHeight = 16
                
                local barBg = CreateFrame("Frame", nil, slotFrame)
                barBg:SetSize(barWidth, barHeight)
                barBg:SetPoint("TOP", slotFrame, "TOP", 0, barY)
                
                -- Apply border to progress bar using accent color
                if ApplyVisuals then
                    local accentBorderColor = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}
                    ApplyVisuals(barBg, {0.05, 0.05, 0.07, 0.3}, accentBorderColor)
                end
                
                -- Progress Fill
                local fillPercent = slot.current / slot.max
                local fillWidth = (barWidth - 2) * fillPercent
                if fillWidth > 0 then
                    local fill = barBg:CreateTexture(nil, "ARTWORK")
                    fill:SetPoint("LEFT", barBg, "LEFT", 1, 0)
                    fill:SetSize(fillWidth, barHeight - 2)
                    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
                    fill:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
                    end
                
                -- Checkpoint Markers (only at thresholds: 1, 4, 8, etc.)
                for i, threshold in ipairs(slot.thresholds) do
                    local checkpointSlot = slot.slotData[i]
                    local slotProgress = math.min(slot.current, threshold)
                    local completed = slot.current >= threshold
                    
                    -- Position on bar
                    local markerXPercent = threshold / slot.max
                    local markerX = markerXPercent * barWidth
                    
                    -- Checkpoint arrow (MiniMap-QuestArrow) - below bar, centered on border
                    local checkArrow = barBg:CreateTexture(nil, "OVERLAY")
                    checkArrow:SetSize(24, 24)
                    checkArrow:SetPoint("CENTER", barBg, "BOTTOMLEFT", markerX, 0)  -- Center on bottom border
                    checkArrow:SetAtlas("MiniMap-QuestArrow")
                    if completed then
                        checkArrow:SetVertexColor(0.2, 1, 0.2, 1)  -- Bright green
                    else
                        checkArrow:SetVertexColor(0.9, 0.9, 0.9, 1)  -- Bright gray/white
                    end
                    
                    -- Checkpoint label (below bar)
                    if completed then
                        -- Green checkmark texture
                        local checkFrame = CreateFrame("Frame", nil, slotFrame)
                        checkFrame:SetSize(16, 16)
                        checkFrame:SetPoint("TOP", barBg, "BOTTOMLEFT", markerX, -12)
                        
                        local checkmark = checkFrame:CreateTexture(nil, "OVERLAY")
                        checkmark:SetAllPoints()
                        checkmark:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
                    else
                        -- Progress text
                        local label = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        label:SetPoint("TOP", barBg, "BOTTOMLEFT", markerX, -8)
                        label:SetTextColor(1, 1, 1)
                        label:SetText(string.format("%d/%d", slotProgress, threshold))
                    end
                    
                    -- Hidden checkbox for manual override (on checkpoint line)
                    local checkbox = CreateThemedCheckbox(slotFrame, checkpointSlot.completed)
                    checkbox:SetSize(8, 8)
                    checkbox:SetPoint("CENTER", barBg, "LEFT", markerX, 0)
                    checkbox:SetAlpha(0.01)
                    checkbox:SetScript("OnClick", function(self)
                        checkpointSlot.completed = self:GetChecked()
                        checkpointSlot.manualOverride = true
                    end)
                end
            end
            
            -- Update yOffset
            -- yOffset updated by layout manager
        
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
            
            -- Accent border for daily quest header
            if ApplyVisuals then
                local borderColor = {0.30, 0.90, 0.30, 0.8}
                ApplyVisuals(headerCard, {0.08, 0.08, 0.10, 1}, borderColor)
            end
            
            -- Get character class color
            local classColor = {1, 1, 1}
            if plan.characterClass then
                local classColors = RAID_CLASS_COLORS[plan.characterClass]
                if classColors then
                    classColor = {classColors.r, classColors.g, classColors.b}
                end
            end
            
            -- === HEADER ===
            local iconBorder = CreateFrame("Frame", nil, headerCard)
            iconBorder:SetSize(42, 42)
            iconBorder:SetPoint("LEFT", 10, 0)
            -- Icon border removed (naked frame)
            -- Icon border removed (naked frame)
            
            local iconFrameObj = CreateIcon(headerCard, plan.icon, 38, false, nil, false)
            iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
            
            -- Title
            local titleText = headerCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleText:SetPoint("LEFT", iconBorder, "RIGHT", 10, 10)
            titleText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
            titleText:SetText("Daily Tasks - " .. (plan.contentName or "Unknown"))
            
            -- Character name
            local charText = headerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
            
            local summaryText = headerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            summaryText:SetPoint("RIGHT", -50, 0)
            if completedQuests == totalQuests and totalQuests > 0 then
                summaryText:SetTextColor(0.3, 1, 0.3)
            else
                summaryText:SetTextColor(1, 1, 1)
            end
            summaryText:SetText(string.format("%d/%d", completedQuests, totalQuests))
            
            -- Remove button
            local removeBtn = CreateFrame("Button", nil, headerCard)
            removeBtn:SetSize(16, 16)
            removeBtn:SetPoint("TOPRIGHT", -6, -6)
            local removeBtnText = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            removeBtnText:SetPoint("CENTER")
            removeBtnText:SetText("|cffff6060×|r")
            removeBtnText:SetFont(removeBtnText:GetFont(), 16, "THICKOUTLINE")
            removeBtn:SetScript("OnEnter", function(self)
                removeBtnText:SetText("|cffff0000×|r")
            end)
            removeBtn:SetScript("OnLeave", function(self)
                removeBtnText:SetText("|cffff6060×|r")
            end)
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
                            
                            -- Icon with border
                            local iconBorder = CreateFrame("Frame", nil, questCard)
                            iconBorder:SetSize(46, 46)
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
                            local questTitle = questCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                            questTitle:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
                            questTitle:SetPoint("RIGHT", questCard, "RIGHT", -10, 0)
                            questTitle:SetText("|cffffffff" .. (quest.title or "Unknown Quest") .. "|r")
                            questTitle:SetJustifyH("LEFT")
                            questTitle:SetWordWrap(true)
                            questTitle:SetMaxLines(2)
                            
                            -- Quest type badge with icon (like other cards)
                            local questIconFrame = CreateFrame("Frame", nil, questCard)
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
                            
                            local questTypeBadge = questCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
                            local descText = questCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
                                
                                local timeText = questCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                                timeText:SetPoint("BOTTOMLEFT", 10, 6)
                                timeText:SetText("|TInterface\\COMMON\\UI-TimeIcon:16:16|t " .. timeColor .. timeStr .. "|r")
                            end
                            
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
                
                local noQuestsText = noQuestsCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
                local completeBtn = CreateFrame("Button", nil, card)
                completeBtn:SetSize(20, 20)
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
            
            local removeBtn = CreateFrame("Button", nil, card)
            removeBtn:SetSize(20, 20)
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
    local COLORS = GetCOLORS()
    
    -- UNIFIED: Check if CollectionScanner is ready
    if self.CollectionScanner and not self.CollectionScanner:IsReady() then
        local progress = self.CollectionScanner:GetProgress()
        
        -- Show scanning progress banner
        local bannerCard = CreateCard(parent, 100)
        bannerCard:SetPoint("TOPLEFT", 10, -yOffset)
        bannerCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local titleText = bannerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleText:SetPoint("CENTER", 0, 20)
        titleText:SetTextColor(0.3, 0.8, 1.0)
        titleText:SetText("🔄 Scanning Collections...")
        
        local progressText = bannerCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        progressText:SetPoint("TOP", titleText, "BOTTOM", 0, -10)
        progressText:SetTextColor(1, 1, 1)  -- White
        progressText:SetText(string.format("Progress: %d%%", progress.percent or 0))
        
        local hintText = bannerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hintText:SetPoint("TOP", progressText, "BOTTOM", 0, -10)
        hintText:SetTextColor(1, 1, 1)  -- White
        hintText:SetText("This only happens once after login. Results will be instant when ready!")
        
        return yOffset + 120
    end
    
    -- Use SharedWidgets search bar (like Items tab)
    -- Create results container that can be refreshed independently
    local resultsContainer = CreateResultsContainer(parent, yOffset + 40, 10)
    
    local searchContainer = CreateSearchBox(parent, width, "Search " .. category .. "s...", function(text)
        searchText = text
        browseResults = {}
        
        -- Clear only the results container, not the search box
        if resultsContainer then
            local children = {resultsContainer:GetChildren()}
            for _, child in ipairs(children) do
                child:Hide()
                child:SetParent(nil)
            end
        end
        
        -- Redraw only results in the container
        local resultsYOffset = 0
        self:DrawBrowserResults(resultsContainer, resultsYOffset, width, category, searchText)
    end, 0.3, searchText)
    searchContainer:SetPoint("TOPLEFT", 10, -yOffset)
    searchContainer:SetPoint("TOPRIGHT", -10, -yOffset)
    
    yOffset = yOffset + 40
    
    -- Initial draw of results
    local resultsYOffset = 0
    self:DrawBrowserResults(resultsContainer, resultsYOffset, width, category, searchText)
    
    return yOffset + 1800  -- Approximate height
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
    local COLORS = GetCOLORS()
    local rowKey = "achievement_row_" .. achievement.id
    local rowExpanded = expandedGroups[rowKey] or false
    
    -- Get FRESH criteria count from API
    local freshNumCriteria = GetAchievementNumCriteria(achievement.id)
    
    -- Build Information section (always shown when expanded)
    local informationText = ""
    if achievement.description and achievement.description ~= "" then
        informationText = achievement.description
    end
    if achievement.rewardText and achievement.rewardText ~= "" then
        if informationText ~= "" then
            informationText = informationText .. "\n\n"
        end
        informationText = informationText .. "|cffffcc00Reward:|r " .. achievement.rewardText
    end
    if informationText == "" then
        informationText = "|cff888888No additional information|r"
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
                
                local statusIcon = completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t" or "|cff888888•|r"
                local textColor = completed and "|cffaaaaaa" or "|cffdddddd"
                local progressText = ""
                
                if quantity and reqQuantity and reqQuantity > 0 then
                    progressText = string.format(" |cff888888(%d/%d)|r", quantity, reqQuantity)
                end
                
                table.insert(criteriaDetails, statusIcon .. " " .. textColor .. criteriaName .. "|r" .. progressText)
            end
        end
        
        if #criteriaDetails > 0 then
            local progressPercent = math.floor((completedCount / freshNumCriteria) * 100)
            local progressColor = (completedCount == freshNumCriteria) and "|cff00ff00" or "|cffffffff"
            requirementsText = string.format("%s%d of %d (%d%%)|r\n", progressColor, completedCount, freshNumCriteria, progressPercent)
            requirementsText = requirementsText .. table.concat(criteriaDetails, "\n")
        else
            requirementsText = "|cff888888No criteria found|r"
        end
    else
        requirementsText = "|cff888888No requirements (instant completion)|r"
    end
    
    -- Prepare row data for CreateExpandableRow
    local rowData = {
        icon = achievement.icon,
        score = achievement.points,
        title = achievement.name,
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
            WarbandNexus:RefreshUI()
        end
    )
    
    -- Set alternating colors (using standard UI_LAYOUT colors)
    if animIdx % 2 == 0 then
        row.bgColor = UI_LAYOUT.ROW_COLOR_EVEN
    else
        row.bgColor = UI_LAYOUT.ROW_COLOR_ODD
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
    
    -- Add "+ Add" button or "Added" indicator
    if achievement.isPlanned then
        -- Show green checkmark + "Added" text (no button)
        -- Match button size for symmetry: 70 width, 28 height (same as CreateThemedButton)
        local addedFrame = CreateFrame("Frame", nil, row.headerFrame)
        addedFrame:SetSize(70, 28)
        addedFrame:SetPoint("RIGHT", -6, 0)
        
        local addedIcon = CreateIcon(addedFrame, ICON_CHECK, 14, false, nil, true)
        addedIcon:SetPoint("LEFT", 6, 0)  -- 6px inset to match button padding
        
        -- Use same font as button (GameFontNormal) for consistency
        local addedText = addedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        addedText:SetPoint("LEFT", addedIcon, "RIGHT", 4, 0)
        addedText:SetText("|cff88ff88Added|r")
        
        row.addedIndicator = addedFrame
    else
        -- Show "+ Add" button
        local addBtn = CreateThemedButton(row.headerFrame, "+ Add", 70)
        addBtn:SetPoint("RIGHT", -6, 0)
        addBtn:SetFrameLevel(row.headerFrame:GetFrameLevel() + 10)
        addBtn:EnableMouse(true)
        addBtn:RegisterForClicks("LeftButtonUp")
        addBtn.achievementData = achievement
        
        -- Prevent click propagation to header (stop expand/collapse when clicking button)
        addBtn:SetScript("OnMouseDown", function(self, button)
            -- Stop propagation
        end)
        
        addBtn:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                WarbandNexus:AddPlan({
                    type = PLAN_TYPES.ACHIEVEMENT,
                    achievementID = self.achievementData.id,
                    name = self.achievementData.name,
                    icon = self.achievementData.icon,
                    points = self.achievementData.points,
                    source = self.achievementData.source
                })
                
                -- Hide button and show "Added" indicator
                self:Hide()
                
                -- Create "Added" indicator
                -- Match button size for symmetry: 70 width, 28 height (same as CreateThemedButton)
                local addedFrame = CreateFrame("Frame", nil, row.headerFrame)
                addedFrame:SetSize(70, 28)
                addedFrame:SetPoint("RIGHT", -6, 0)
                
                local addedIcon = CreateIcon(addedFrame, ICON_CHECK, 14, false, nil, true)
                addedIcon:SetPoint("LEFT", 6, 0)  -- 6px inset to match button padding
                
                -- Use same font as button (GameFontNormal) for consistency
                local addedText = addedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                addedText:SetPoint("LEFT", addedIcon, "RIGHT", 4, 0)
                addedText:SetText("|cff88ff88Added|r")
                
                row.addedIndicator = addedFrame
                
                -- Update achievement flag
                achievement.isPlanned = true
                
                -- Refresh UI (will update all other instances)
                WarbandNexus:RefreshUI()
            end
        end)
    end
    
    -- Return new yOffset
    return yOffset + row:GetHeight() + 2
end

function WarbandNexus:DrawAchievementsTable(parent, results, yOffset, width)
    local COLORS = GetCOLORS()
    
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
        
        -- Draw root category header
        local rootKey = "achievement_cat_" .. rootCategoryID
        local rootExpanded = self.achievementsExpandAllActive or expandedGroups[rootKey]
        
        local rootHeader = CreateCollapsibleHeader(
            parent,
            string.format("%s (%d)", rootCategory.name, totalAchievements),
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
        
        yOffset = yOffset + UI_LAYOUT.HEADER_HEIGHT
        
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
                
                -- Draw sub-category header (indented) - even if empty
                local childKey = "achievement_cat_" .. childID
                local childExpanded = self.achievementsExpandAllActive or expandedGroups[childKey]
                
                local childHeader = CreateCollapsibleHeader(
                    parent,
                    string.format("%s (%d)", childCategory.name, childAchievementCount),
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
                childHeader:SetPoint("TOPLEFT", UI_LAYOUT.BASE_INDENT, -yOffset) -- Standard indent
                childHeader:SetWidth(width - UI_LAYOUT.BASE_INDENT)
                
                yOffset = yOffset + UI_LAYOUT.HEADER_HEIGHT
                
                -- Draw sub-category content if expanded
                if childExpanded then
                    -- First, draw this category's own achievements
                    if #childCategory.achievements > 0 then
                        for i, achievement in ipairs(childCategory.achievements) do
                            animIdx = animIdx + 1
                            yOffset = RenderAchievementRow(self, parent, achievement, yOffset, width, UI_LAYOUT.BASE_INDENT, animIdx, shouldAnimate, expandedGroups)
                        end
                    end
                    
                    -- Now draw grandchildren categories (3rd level: e.g., Quests > Eastern Kingdoms > Zone)
                    for _, grandchildID in ipairs(childCategory.children or {}) do
                        local grandchildCategory = categoryData[grandchildID]
                        if grandchildCategory and #grandchildCategory.achievements > 0 then
                            -- Draw grandchild category header (double indented)
                            local grandchildKey = "achievement_cat_" .. grandchildID
                            local grandchildExpanded = self.achievementsExpandAllActive or expandedGroups[grandchildKey]
                            
                            local grandchildHeader = CreateCollapsibleHeader(
                                parent,
                                string.format("%s (%d)", grandchildCategory.name, #grandchildCategory.achievements),
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
                            grandchildHeader:SetPoint("TOPLEFT", UI_LAYOUT.BASE_INDENT * 2, -yOffset) -- Double indent (30px)
                            grandchildHeader:SetWidth(width - (UI_LAYOUT.BASE_INDENT * 2))
                            
                            yOffset = yOffset + UI_LAYOUT.HEADER_HEIGHT
                            
                            -- Draw grandchild achievements if expanded
                            if grandchildExpanded then
                                for i, achievement in ipairs(grandchildCategory.achievements) do
                                    animIdx = animIdx + 1
                                    yOffset = RenderAchievementRow(self, parent, achievement, yOffset, width, UI_LAYOUT.BASE_INDENT * 2, animIdx, shouldAnimate, expandedGroups)
                                end
                            end
                        end
                    end
                    
                    -- Show "all completed" message only if no achievements in child AND no grandchildren
                    if #childCategory.achievements == 0 and #childCategory.children == 0 then
                        local noAchievementsText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        noAchievementsText:SetPoint("TOPLEFT", UI_LAYOUT.BASE_INDENT * 2, -yOffset)
                        noAchievementsText:SetText("|cff88cc88✓ You already completed all achievements in this category!|r")
                        yOffset = yOffset + 25
                    end
                end
            end
            
            -- Show "all completed" message only if root has no achievements AND no children
            if #rootCategory.achievements == 0 and #rootCategory.children == 0 then
                local noAchievementsText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                noAchievementsText:SetPoint("TOPLEFT", UI_LAYOUT.BASE_INDENT, -yOffset)
                noAchievementsText:SetText("|cff88cc88✓ You already completed all achievements in this category!|r")
                yOffset = yOffset + 25
            end
        end
        
        -- Spacing after category (WoW-like: compact)
        yOffset = yOffset + SECTION_SPACING + 4
        end -- Close if rootCategory
    end
    
    return yOffset
end

-- ============================================================================
-- BROWSER RESULTS RENDERING (Separated for search refresh)
-- ============================================================================

function WarbandNexus:DrawBrowserResults(parent, yOffset, width, category, searchText)
    local COLORS = GetCOLORS()
    
    -- Get results based on category
    local results = {}
    if category == "mount" then
        results = self:GetUncollectedMounts(searchText, 50)
    elseif category == "pet" then
        results = self:GetUncollectedPets(searchText, 50)
    elseif category == "toy" then
        results = self:GetUncollectedToys(searchText, 50)
    elseif category == "transmog" then
        -- Transmog browser with sub-categories
        return self:DrawTransmogBrowser(parent, yOffset, width)
    elseif category == "illusion" then
        results = self:GetUncollectedIllusions(searchText, 50)
    elseif category == "title" then
        results = self:GetUncollectedTitles(searchText, 50)
    elseif category == "achievement" then
        results = self:GetUncollectedAchievements(searchText, 99999) -- Very high limit - effectively unlimited
        
        -- Update isPlanned flags for achievements
        for _, item in ipairs(results) do
            item.isPlanned = self:IsAchievementPlanned(item.id)
        end
        
        -- Use table-based view for achievements
        return self:DrawAchievementsTable(parent, results, yOffset, width)
    elseif category == "recipe" then
        -- Recipes require profession window to be open - show message
        local helpCard = CreateCard(parent, 80)
        helpCard:SetPoint("TOPLEFT", 0, -yOffset)
        helpCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local helpText = helpCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        helpText:SetPoint("CENTER", 0, 10)
        helpText:SetText("|cffffcc00Recipe Browser|r")
        
        local helpDesc = helpCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        helpDesc:SetPoint("TOP", helpText, "BOTTOM", 0, -8)
        helpDesc:SetText("|cff888888Open your Profession window in-game to browse recipes.\nThe addon will scan available recipes when the window is open.|r")
        helpDesc:SetJustifyH("CENTER")
        helpDesc:SetWidth(width - 40)
        
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
        local noResultsCard = CreateCard(parent, 80)
        noResultsCard:SetPoint("TOPLEFT", 0, -yOffset)
        noResultsCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local noResultsText = noResultsCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        noResultsText:SetPoint("CENTER", 0, 10)
        noResultsText:SetTextColor(1, 1, 1)  -- White
        noResultsText:SetText("No " .. category .. "s found")
        
        local noResultsDesc = noResultsCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
        noResultsDesc:SetTextColor(1, 1, 1)  -- White
        noResultsDesc:SetText("Try adjusting your search or filters.")
        
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
            
            local noResultsText = noResultsCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            noResultsText:SetPoint("CENTER", 0, 10)
            noResultsText:SetTextColor(0.3, 1, 0.3)
            noResultsText:SetText("No collected " .. category .. "s yet")
            
            local noResultsDesc = noResultsCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
            noResultsDesc:SetTextColor(1, 1, 1)  -- White
            noResultsDesc:SetText("Start collecting to see them here!")
            
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
            
            local noResultsText = noResultsCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            noResultsText:SetPoint("CENTER", 0, 10)
            noResultsText:SetTextColor(0.3, 1, 0.3)
            noResultsText:SetText("All " .. category .. "s collected!")
            
            local noResultsDesc = noResultsCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
            noResultsDesc:SetTextColor(1, 1, 1)  -- White
            noResultsDesc:SetText("You've collected everything in this category!")
            
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
        local iconBorder = CreateFrame("Frame", nil, card)
        iconBorder:SetSize(46, 46)
        iconBorder:SetPoint("TOPLEFT", 10, -10)
        -- Icon border removed (naked frame)
        
        local iconFrameObj = CreateIcon(card, item.icon or "Interface\\Icons\\INV_Misc_QuestionMark", 42, false, nil, false)
        iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
        -- TexCoord already applied by CreateIcon factory
        
        -- === TITLE ===
        local nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
        nameText:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        nameText:SetText("|cffffffff" .. (item.name or "Unknown") .. "|r")
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(true)
        nameText:SetMaxLines(2)
        nameText:SetNonSpaceWrap(false)
        
        -- === POINTS / TYPE BADGE (directly under title, NO spacing) ===
        if category == "achievement" and item.points then
            -- Achievement: Show shield icon + points (like in My Plans)
            local shieldFrame = CreateFrame("Frame", nil, card)
            shieldFrame:SetSize(20, 20)
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
            end
            
            local pointsText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            pointsText:SetPoint("LEFT", shieldFrame, "RIGHT", 4, 0)
            pointsText:SetText(string.format("|cff%02x%02x%02x%d Points|r", 
                255*255, 204*255, 51*255,  -- Gold color
                item.points))
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
                iconFrame = CreateFrame("Frame", nil, card)
                iconFrame:SetSize(20, 20)
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
                end
            end
            
            -- Create type badge text
            local typeBadge = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
        if firstSource.vendor then
            local vendorText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            vendorText:SetPoint("TOPLEFT", 10, line3Y)
            vendorText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            vendorText:SetText("|A:Class:16:16|a Vendor: " .. firstSource.vendor)
            vendorText:SetTextColor(1, 1, 1)
            vendorText:SetJustifyH("LEFT")
            vendorText:SetWordWrap(true)
            vendorText:SetMaxLines(2)
            vendorText:SetNonSpaceWrap(false)
        elseif firstSource.npc then
            local npcText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            npcText:SetPoint("TOPLEFT", 10, line3Y)
            npcText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            npcText:SetText("|A:Class:16:16|a Drop: " .. firstSource.npc)
            npcText:SetTextColor(1, 1, 1)
            npcText:SetJustifyH("LEFT")
            npcText:SetWordWrap(true)
            npcText:SetMaxLines(2)
            npcText:SetNonSpaceWrap(false)
        elseif firstSource.faction then
            local factionText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
            local zoneText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
                    local infoText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    infoText:SetPoint("TOPLEFT", 10, line3Y)
                    infoText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    infoText:SetText("|cff88ff88Information:|r |cffffffff" .. description .. "|r")
                    infoText:SetJustifyH("LEFT")
                    infoText:SetWordWrap(true)
                    infoText:SetMaxLines(2)
                    infoText:SetNonSpaceWrap(false)
                    lastElement = infoText
                elseif item.description and item.description ~= "" then
                    local infoText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    infoText:SetPoint("TOPLEFT", 10, line3Y)
                    infoText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    infoText:SetText("|cff88ff88Information:|r |cffffffff" .. item.description .. "|r")
                    infoText:SetJustifyH("LEFT")
                    infoText:SetWordWrap(true)
                    infoText:SetMaxLines(2)
                    infoText:SetNonSpaceWrap(false)
                    lastElement = infoText
                end
                
                -- === PROGRESS - BELOW information, NO spacing ===
                if progress then
                    local progressText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
                    local rewardText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
                    local sourceText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
        
        -- Add/Planned button (bottom right)
        if item.isPlanned then
            -- Match button size for symmetry: 60 width, 22 height (same as Add button)
            local plannedFrame = CreateFrame("Frame", nil, card)
            plannedFrame:SetSize(60, 22)
            plannedFrame:SetPoint("BOTTOMRIGHT", -8, 8)
            
            local plannedIconFrame = CreateIcon(plannedFrame, ICON_CHECK, 14, false, nil, true)
            plannedIconFrame:SetPoint("LEFT", 6, 0)  -- 6px inset to match button padding
            
            -- Use same font as button (GameFontNormalSmall) for consistency
            local plannedText = plannedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            plannedText:SetPoint("LEFT", plannedIconFrame, "RIGHT", 4, 0)
            plannedText:SetText("|cff88ff88Planned|r")
        else
            -- Create themed "+ Add" button using SharedWidgets colors
            local addBtn = CreateFrame("Button", nil, card)
            addBtn:SetSize(60, 22)
            addBtn:SetPoint("BOTTOMRIGHT", -8, 8)
            
            -- Apply border and hover effect to Add button
            if ApplyVisuals then
                ApplyVisuals(addBtn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
            end
            if ApplyHoverEffect then
                ApplyHoverEffect(addBtn, 0.25)
            end
            
            local addBtnText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            addBtnText:SetPoint("CENTER", 0, 0)
            addBtnText:SetText("|cffffffff+ Add|r")
            addBtn:SetScript("OnClick", function()
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
                
                -- Update card border to green immediately (added/planned state)
                if UpdateBorderColor then
                    UpdateBorderColor(card, {0.30, 0.90, 0.30, 0.8})
                end
                
                -- Hide the Add button and show Planned text
                addBtn:Hide()
                local plannedFrame = CreateFrame("Frame", nil, card)
                -- Match button size for symmetry: 60 width, 22 height (same as Add button)
                plannedFrame:SetSize(60, 22)
                plannedFrame:SetPoint("BOTTOMRIGHT", -8, 8)
                
                local plannedIconFrame = CreateIcon(plannedFrame, ICON_CHECK, 14, false, nil, true)
                plannedIconFrame:SetPoint("LEFT", 6, 0)  -- 6px inset to match button padding
                
                -- Use same font as button (GameFontNormalSmall) for consistency
                local plannedText = plannedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                plannedText:SetPoint("LEFT", plannedIconFrame, "RIGHT", 4, 0)
                plannedText:SetText("|cff88ff88Planned|r")
            end)
        end
        
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
        local noResults = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noResults:SetPoint("TOP", 0, -yOffset - 30)
        noResults:SetText("|cff888888No results found. Try a different search.|r")
        yOffset = yOffset + 80
    end
    
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
    
    local COLORS = GetCOLORS()
    
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
    
    -- Character section with icon
    local charFrame = CreateFrame("Frame", nil, contentFrame)
    charFrame:SetSize(420, 45)
    charFrame:SetPoint("TOP", 0, -15)
    
    -- Get race-gender info
    local _, englishRace = UnitRace("player")
    local gender = UnitSex("player")
    local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
    
    -- Character race icon with border
    local iconContainer = CreateFrame("Frame", nil, charFrame)
    iconContainer:SetSize(36, 36)
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
    
    -- Character name with class color (larger font)
    local charText = charFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    charText:SetPoint("LEFT", iconContainer, "RIGHT", 10, 0)
    if classColors then
        charText:SetTextColor(classColors.r, classColors.g, classColors.b)
    else
        charText:SetTextColor(1, 0.8, 0)
    end
    charText:SetText(currentName .. "-" .. currentRealm)
    
    -- Title label
    local titleLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", 12, -75)
    titleLabel:SetText("|cff" .. string.format("%02x%02x%02x", COLORS.accent[1]*255, COLORS.accent[2]*255, COLORS.accent[3]*255) .. "Title:|r")
    
    -- Title input container
    local titleInputBg = CreateFrame("Frame", nil, contentFrame)
    titleInputBg:SetSize(410, 35)
    titleInputBg:SetPoint("TOPLEFT", 12, -97)
    
    -- Apply border to input
    if ApplyVisuals then
        ApplyVisuals(titleInputBg, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    local titleInput = CreateFrame("EditBox", nil, titleInputBg)
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
    local descLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    descLabel:SetPoint("TOPLEFT", 12, -145)
    descLabel:SetText("|cff" .. string.format("%02x%02x%02x", COLORS.accent[1]*255, COLORS.accent[2]*255, COLORS.accent[3]*255) .. "Description:|r")
    
    -- Description input container (scrollable, single line)
    local descInputBg = CreateFrame("Frame", nil, contentFrame)
    descInputBg:SetSize(410, 35)  -- Reduced height for single line
    descInputBg:SetPoint("TOPLEFT", 12, -167)
    
    -- Apply border to input
    if ApplyVisuals then
        ApplyVisuals(descInputBg, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    local descInput = CreateFrame("EditBox", nil, descInputBg)
    descInput:SetSize(395, 30)
    descInput:SetPoint("LEFT", 8, 0)
    descInput:SetFontObject(ChatFontNormal)
    descInput:SetTextColor(1, 1, 1, 1)
    descInput:SetAutoFocus(false)
    descInput:SetMultiLine(false)  -- Single line only - prevents Enter from creating new lines
    descInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    descInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    -- Limit to 300 characters only (no word limit)
    descInput:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        -- Remove any newlines that might have been inserted
        text = text:gsub("[\n\r]", " ")
        
        -- Enforce 300 character limit
        local maxChars = 300
        if string.len(text) > maxChars then
            text = string.sub(text, 1, maxChars)
            local cursorPos = self:GetCursorPosition()
            self:SetText(text)
            self:SetCursorPosition(math.min(cursorPos, maxChars))
        else
            -- Update text to remove newlines
            if text ~= self:GetText() then
                local cursorPos = self:GetCursorPosition()
                self:SetText(text)
                self:SetCursorPosition(math.min(cursorPos, string.len(text)))
            end
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
            local status = plan.completed and "|cff00ff00completed|r" or "|cff888888marked as incomplete|r"
            self:Print("Custom plan '" .. plan.name .. "' " .. status)
            
            -- Show notification if completed
            if plan.completed and self.ShowToastNotification then
                self:ShowToastNotification({
                    icon = plan.icon or "Interface\\Icons\\INV_Misc_Note_01",
                    title = "Plan Completed!",
                    subtitle = "Custom Goal Achieved",
                    message = plan.name,
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
    local COLORS = GetCOLORS()
    
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
        local warningIcon = warningIconFrame3.texture
        
        local warningText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        warningText:SetPoint("TOP", warningIcon, "BOTTOM", 0, -15)
        warningText:SetText("|cffff9900Weekly Plan Already Exists|r")
        
        local infoText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
        
        -- Character section with icon (centered)
        local charFrame = CreateFrame("Frame", nil, contentFrame)
        charFrame:SetSize(300, 45)  -- Narrower, centered width
        charFrame:SetPoint("TOP", 0, -15)  -- Perfectly centered
        
        -- Character race and class info
        local _, currentClass = UnitClass("player")
        local classColors = RAID_CLASS_COLORS[currentClass]
        local _, englishRace = UnitRace("player")
        local gender = UnitSex("player")
        local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
        
        -- Character race icon with border (centered within charFrame)
        local iconContainer = CreateFrame("Frame", nil, charFrame)
        iconContainer:SetSize(36, 36)
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
        
        -- Character name with class color (larger font)
        local charName = charFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
            local progressHeader = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
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
                
                -- Main column card
                local col = CreateFrame("Frame", nil, contentFrame)
                col:SetSize(colWidth, 150)  -- Increased height for stars
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
                
                -- Title (below icon, larger)
                local titleText = col:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                titleText:SetPoint("TOP", iconFrame2, "BOTTOM", 0, -8)
                titleText:SetTextColor(0.95, 0.95, 0.95)
                titleText:SetText(title)
                
                -- Reward tier indicators (stars) - Inside card, bigger, with milestone text
                local starSpacing = 42
                local starSize = 24  -- Bigger stars
                local starTotalWidth = (3 - 1) * starSpacing
                local starStartX = -starTotalWidth / 2
                
                for i = 1, 3 do
                    -- Star container
                    local starContainer = CreateFrame("Frame", nil, col)
                    starContainer:SetSize(starSize, starSize + 20)  -- Extra height for text
                    starContainer:SetPoint("TOP", titleText, "BOTTOM", starStartX + (i - 1) * starSpacing, -12)
                    
                    -- Star texture
                    local starFrame = CreateFrame("Frame", nil, starContainer)
                    starFrame:SetSize(starSize, starSize)
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
                    local milestoneText = starContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    milestoneText:SetPoint("TOP", starFrame, "BOTTOM", 0, -3)
                    
                    if isComplete then
                        milestoneText:SetTextColor(0.3, 1, 0.3)  -- Green (complete)
                    else
                        milestoneText:SetTextColor(0.6, 0.6, 0.6)  -- Gray
                    end
                    milestoneText:SetText(string.format("%d/%d", math.min(current, thresholds[i]), thresholds[i]))
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
    local COLORS = GetCOLORS()
    
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
        local warningIcon = warningIconFrame2.texture
        
        local warningText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        warningText:SetPoint("TOP", warningIcon, "BOTTOM", 0, -10)
        warningText:SetText("|cffff9900Daily Plan Already Exists|r")
        
        local infoText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    
    -- Character display with icon and border
    local charFrame = CreateFrame("Frame", nil, contentFrame)
    charFrame:SetSize(460, 45)
    charFrame:SetPoint("TOP", 0, -15)
    
    -- Get race-gender info
    local _, englishRace = UnitRace("player")
    local gender = UnitSex("player") -- 2 = male, 3 = female
    local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
    
    -- Character race icon with border
    local iconContainer = CreateFrame("Frame", nil, charFrame)
    iconContainer:SetSize(36, 36)
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
    
    -- Character name with class color (larger font)
    local charText = charFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    charText:SetPoint("LEFT", iconContainer, "RIGHT", 10, 0)
    if classColors then
        charText:SetTextColor(classColors.r, classColors.g, classColors.b)
    else
        charText:SetTextColor(1, 0.8, 0)
    end
    charText:SetText(currentName .. "-" .. currentRealm)
    
    -- Content selection
    local contentY = -75
    local contentLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
        local btn = CreateFrame("Button", nil, contentFrame)
        btn:SetSize(180, 50)
        btn:SetPoint("TOPLEFT", 12, contentBtnY - (i-1) * 60)
        
        -- Apply border to content selection buttons
        if ApplyVisuals then
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
        if ApplyHoverEffect then
            ApplyHoverEffect(btn, 0.25)
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
        local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", iconFrame3, "RIGHT", 10, 0)
        nameText:SetText(content.name)
        
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
    local questTypeLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
        
        local label = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", cb, "RIGHT", 8, 5)  -- Moved up 5 pixels
        label:SetText(questType.name)
        
        local desc = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    local COLORS = GetCOLORS()
    
    -- Work in Progress screen
    local wipCard = CreateCard(parent, 200)
    wipCard:SetPoint("TOPLEFT", 0, -yOffset)
    wipCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local wipIconFrame2 = CreateIcon(wipCard, "Interface\\Icons\\INV_Misc_EngGizmos_20", 64, false, nil, true)
    wipIconFrame2:SetPoint("TOP", 0, -30)
    local wipIcon = wipIconFrame2.texture
    
    local wipTitle = wipCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    wipTitle:SetPoint("TOP", wipIcon, "BOTTOM", 0, -20)
    wipTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    wipTitle:SetText("Work in Progress")
    
    local wipDesc = wipCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wipDesc:SetPoint("TOP", wipTitle, "BOTTOM", 0, -15)
    wipDesc:SetWidth(width - 100)
    wipDesc:SetTextColor(1, 1, 1)  -- White
    wipDesc:SetJustifyH("CENTER")
    wipDesc:SetText("Transmog collection tracking is currently under development.\n\nThis feature will be available in a future update with improved\nperformance and better integration with Warband systems.")
    
    return yOffset + 230
end

