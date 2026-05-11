--[[
    Warband Nexus - Plans Tab UI
    User-driven goal tracker for mounts, pets, and toys
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager  -- Centralized font management

local issecretvalue = issecretvalue

--- Lowercase for search only when the string is safe to touch (Midnight 12.0+).
local function SafeLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

--- Display-safe player name / realm (Midnight: never concatenate secret API strings).
local function SafePlayerName()
    local n = UnitName("player")
    if not n or (issecretvalue and issecretvalue(n)) then return nil end
    return n
end
local function SafeRealmName()
    local r = GetRealmName and GetRealmName()
    if not r or (issecretvalue and issecretvalue(r)) then return nil end
    return r
end

-- Unique AceEvent handler identity for PlansUI
local PlansUIEvents = {}

-- Expand state for the To-Do List rows (mirrors PlansTrackerWindow). Keyed by plan.id so
-- the user's open/closed choices survive across PopulateContent rebuilds.
local expandedPlans = {}

-- Debug print helper
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

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
local CreateExpandableRow = ns.UI_CreateExpandableRow
local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
local CardLayoutManager = ns.UI_CardLayoutManager
local BuildAccordionVisualOpts = ns.UI_BuildAccordionVisualOpts

-- Loading state for collection scanning (per-category)
ns.PlansLoadingState = ns.PlansLoadingState or {
    -- Structure: { mount = { isLoading, loader }, pet = { isLoading, loader }, toy = { isLoading, loader } }
}

-- Cached achievement category tree (only changes on reload; GetCategoryList/GetCategoryInfo are static)
local cachedCategoryTree = nil
local PlanCardFactory = ns.UI_PlanCardFactory
local FormatNumber = ns.UI_FormatNumber
local FormatTextNumbers = ns.UI_FormatTextNumbers

--- Session cache: achievementID -> { points, numCriteria, criteriaText, criteriaItems, information }
local function PlansAchievementSessionCache()
    local c = ns._plansAchievementExpandCache
    if not c then
        c = {}
        ns._plansAchievementExpandCache = c
    end
    return c
end

--- Populate once per achievementID per session (Midnight: guard API strings before use).
local function EnsurePlansAchievementExpandCache(achievementID)
    if not achievementID or type(achievementID) ~= "number" then return nil end
    if issecretvalue and issecretvalue(achievementID) then return nil end

    local cache = PlansAchievementSessionCache()
    local existing = cache[achievementID]
    if existing then return existing end

    local entry = {
        points = nil,
        numCriteria = 0,
        criteriaText = nil,
        criteriaItems = nil,
        information = nil,
    }

    local ok, _, _, pointsRaw, _, _, _, achDesc = pcall(GetAchievementInfo, achievementID)
    if not ok then
        cache[achievementID] = entry
        return entry
    end

    if achDesc and achDesc ~= "" then
        if not (issecretvalue and issecretvalue(achDesc)) then
            entry.information = "|cff99ccff" .. achDesc .. "|r"
        end
    end

    local ptsNum = nil
    if pointsRaw ~= nil and not (issecretvalue and issecretvalue(pointsRaw)) then
        ptsNum = tonumber(pointsRaw)
    end
    entry.points = ptsNum or 0

    local numCriteria = (GetAchievementNumCriteria and GetAchievementNumCriteria(achievementID)) or 0
    if numCriteria ~= nil and issecretvalue and issecretvalue(numCriteria) then
        numCriteria = 0
    end
    numCriteria = tonumber(numCriteria) or 0
    entry.numCriteria = numCriteria

    if numCriteria > 0 then
        local completed = 0
        local items = {}
        for cidx = 1, numCriteria do
            local cName, _, cDone, qty, reqQty = GetAchievementCriteriaInfo(achievementID, cidx)
            if cName and cName ~= "" and not (issecretvalue and issecretvalue(cName)) then
                if cDone then completed = completed + 1 end
                local progress = ""
                if qty and reqQty and not (issecretvalue and issecretvalue(qty)) and not (issecretvalue and issecretvalue(reqQty)) then
                    local rq = tonumber(reqQty)
                    if rq and rq > 1 then
                        progress = format(" (%s / %s)", FormatNumber(qty), FormatNumber(reqQty))
                    end
                end
                local icon = cDone and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t" or "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
                items[#items + 1] = { text = icon .. " " .. cName .. progress, completed = cDone }
            end
        end
        entry.criteriaItems = items
        local pct = numCriteria > 0 and math.floor((completed / numCriteria) * 100) or 0
        local achFmt = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_FORMAT"]) or "%s of %s (%s%%)"
        entry.criteriaText = format(achFmt, FormatNumber(completed), FormatNumber(numCriteria), FormatNumber(pct))
    end

    cache[achievementID] = entry
    return entry
end
local NormalizeColonLabelSpacing = ns.UI_NormalizeColonLabelSpacing
local format = string.format

-- Import shared UI layout constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local ROW_HEIGHT = GetLayout().rowHeight or 26
local ROW_SPACING = GetLayout().rowSpacing or 28
local HEADER_SPACING = GetLayout().HEADER_SPACING or GetLayout().headerSpacing or 44
local SECTION_SPACING = GetLayout().SECTION_SPACING or GetLayout().betweenSections or 8
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or GetLayout().sideMargin or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or GetLayout().topMargin or 8

-- Import PLAN_TYPES from PlansManager
local PLAN_TYPES = ns.PLAN_TYPES

-- Category definitions – My Plans always first, rest alphabetical
local CATEGORIES = {
    { key = "active", name = (ns.L and ns.L["CATEGORY_MY_PLANS"]) or "To-Do List", icon = "Interface\\Icons\\INV_Misc_Map_01" },
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
-- Checkbox mirrors (synced from DB each DrawPlansTab; file load can run before AceDB exists)
local showCompleted = false
local showPlanned = false

--- Normalize profile booleans (CheckButton uses 1/nil; AceDB may store true/false).
local function ProfileBool(profile, key, default)
    if not profile then return default end
    local v = profile[key]
    if v == true or v == 1 then return true end
    if v == false or v == nil or v == 0 then return false end
    return default
end

local function NormalizeCheckButtonChecked(button)
    if not button then return false end
    local v = button:GetChecked()
    return v == true or v == 1
end

--- Browse subtabs only: merge collected + uncollected using isPlanned and the two checkboxes.
--- To-Do List / Weekly Progress do not use this — they filter plans in DrawActivePlans (Show Completed only).
local function MergePlansBrowseResults(collectedList, uncollectedList, showPlanned, showCompleted)
    if showCompleted and showPlanned then
        local seen, out = {}, {}
        for i = 1, #(uncollectedList or {}) do
            local item = uncollectedList[i]
            local id = item and item.id
            if item and item.isPlanned and id and not seen[id] then
                seen[id] = true
                out[#out + 1] = item
            end
        end
        for i = 1, #(collectedList or {}) do
            local item = collectedList[i]
            local id = item and item.id
            if item and item.isPlanned and id and not seen[id] then
                seen[id] = true
                out[#out + 1] = item
            end
        end
        return out
    elseif showCompleted and not showPlanned then
        local out = {}
        for i = 1, #(collectedList or {}) do
            local item = collectedList[i]
            if item and item.isPlanned then
                out[#out + 1] = item
            end
        end
        return out
    elseif showPlanned and not showCompleted then
        local out = {}
        for i = 1, #(uncollectedList or {}) do
            local item = uncollectedList[i]
            if item and item.isPlanned then
                out[#out + 1] = item
            end
        end
        return out
    end
    return uncollectedList or {}
end

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
    if type(source) ~= "string" then return parts end
    if issecretvalue and issecretvalue(source) then return parts end
    
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
    if type(cleanSource) ~= "string" or (issecretvalue and issecretvalue(cleanSource)) then
        return parts
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
    
    for ei = 1, #sourcePatterns do
        local entry = sourcePatterns[ei]
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

    -- Default: To-Do List ("active"). Same session: remember last category until /reload.
    do
        local validCat = {}
        for i = 1, #CATEGORIES do
            validCat[CATEGORIES[i].key] = true
        end
        local sc = ns._sessionPlansCategory
        if sc and validCat[sc] then
            currentCategory = sc
        else
            currentCategory = "active"
        end
    end

    if currentCategory ~= "achievement" then
        ns._plansAchOuterVirtualState = nil
    end

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
    
    -- ===== TITLE CARD (in fixedHeader - non-scrolling) — Characters-tab layout; reserve right for action buttons =====
    local activePlanCount = self:GetActiveNonDailyIncompleteCount()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local collectionPlansLabel = (ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List"
    local titleTextContent = "|cff" .. hexColor .. collectionPlansLabel .. "|r"
    local plansSubtitle = (ns.L and ns.L["PLANS_SUBTITLE_TEXT"]) or "Track your weekly goals & collections"
    local activePlanText = activePlanCount ~= 1
        and format((ns.L and ns.L["ACTIVE_PLANS_FORMAT"]) or "%d active plans", activePlanCount)
        or format((ns.L and ns.L["ACTIVE_PLAN_FORMAT"]) or "%d active plan", activePlanCount)
    local subtitleTextContent = plansSubtitle .. " • " .. activePlanText
    local PLANS_TITLE_RIGHT_RESERVE = 560
    local titleCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "plans",
        titleText = titleTextContent,
        subtitleText = subtitleTextContent,
        textRightInset = PLANS_TITLE_RIGHT_RESERVE,
    }))
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
    -- Only show buttons and "Show Completed" checkbox if module is enabled
    if moduleEnabled then
        local prof = self.db and self.db.profile
        if prof then
            showCompleted = ProfileBool(prof, "plansShowCompleted", false)
            showPlanned = ProfileBool(prof, "plansShowPlanned", false)
        end

        -- Add Custom button (using shared widget)
        local titleCardRightInset = GetLayout().TITLE_CARD_CONTROL_RIGHT_INSET or 20
        local hdrToolbarGap = GetLayout().HEADER_TOOLBAR_CONTROL_GAP or 8
        local addCustomBtn = CreateThemedButton(titleCard, (ns.L and ns.L["ADD_CUSTOM"]) or "Add Custom", 100)
        addCustomBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleCardRightInset, 0)
        -- Store reference for state management
        self.addCustomBtn = addCustomBtn
        addCustomBtn:SetScript("OnClick", function()
            self:ShowCustomPlanDialog()
        end)
        
        -- Add Vault button (using shared widget)
        local addWeeklyBtn = CreateThemedButton(titleCard, (ns.L and ns.L["ADD_VAULT"]) or "Add Vault", 100)
        addWeeklyBtn:SetPoint("RIGHT", addCustomBtn, "LEFT", -hdrToolbarGap, 0)
        addWeeklyBtn:SetScript("OnClick", function()
            self:ShowWeeklyPlanDialog()
        end)
        
        -- Add Quest button (opens Daily Plan dialog)
        local addDailyBtn = CreateThemedButton(titleCard, (ns.L and ns.L["ADD_QUEST"]) or "Add Quest", 100)
        addDailyBtn:SetPoint("RIGHT", addWeeklyBtn, "LEFT", -hdrToolbarGap, 0)
        addDailyBtn:SetScript("OnClick", function()
            self:ShowDailyPlanDialog()
        end)

        -- Checkbox (using shared widget) - Next to Add Quest button
        local checkbox = CreateThemedCheckbox(titleCard, showCompleted)
        if checkbox and checkbox.innerDot then
            checkbox.innerDot:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        end
        if not checkbox then
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint("|cffff0000WN DEBUG: CreateThemedCheckbox returned nil! titleCard:|r", titleCard)
            end
            return
        end
        
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            if not checkbox.HasScript then
                DebugPrint("|cffff0000WN DEBUG: Checkbox missing HasScript method! Type:|r", checkbox:GetObjectType())
            elseif not checkbox:HasScript("OnClick") then
                DebugPrint("|cffffff00WN DEBUG: Checkbox type", checkbox:GetObjectType(), "doesn't support OnClick|r")
            end
        end
        
        -- Reset Completed Plans button (left of Add Quest button)
        local resetBtn = CreateThemedButton(titleCard, (ns.L and ns.L["RESET_LABEL"]) or "Reset", 80)
        resetBtn:SetPoint("RIGHT", addDailyBtn, "LEFT", -hdrToolbarGap, 0)
        
        -- Checkbox (left of Reset button)
        checkbox:SetPoint("RIGHT", resetBtn, "LEFT", -hdrToolbarGap, 0)
        resetBtn:SetScript("OnClick", function()
            -- Confirmation via StaticPopup
            StaticPopupDialogs["WN_RESET_COMPLETED_PLANS"] = {
                text = (ns.L and ns.L["RESET_COMPLETED_CONFIRM"]) or "Are you sure you want to remove ALL completed plans?\n\nThis cannot be undone!",
                button1 = (ns.L and ns.L["YES_RESET"]) or "Yes, Reset",
                button2 = CANCEL or "Cancel",
                OnAccept = function()
                    if WarbandNexus.ResetCompletedPlans then
                        local count = WarbandNexus:ResetCompletedPlans()
                        WarbandNexus:Print(format((ns.L and ns.L["REMOVED_PLANS_FORMAT"]) or "Removed %d completed plan(s).", count))
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
            GameTooltip:SetText((ns.L and ns.L["REMOVE_COMPLETED_TOOLTIP"]) or "Remove all completed plans from your My Plans list. This will delete all completed custom plans and remove completed mounts/pets/toys from your plans. This action cannot be undone!", 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        -- Add text label for "Show Completed" checkbox (left of checkbox)
        local checkboxLabel = FontManager:CreateFontString(titleCard, "body", "OVERLAY")
        checkboxLabel:SetPoint("RIGHT", checkbox, "LEFT", -hdrToolbarGap, 0)
        checkboxLabel:SetText((ns.L and ns.L["SHOW_COMPLETED"]) or "Show Completed")
        checkboxLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        
        -- Override OnClick to add filtering (with safety check)
        local originalOnClick = nil
        if checkbox and checkbox.GetScript then
            local success, result = pcall(function() return checkbox:GetScript("OnClick") end)
            if success then
                originalOnClick = result
            elseif IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint("WarbandNexus DEBUG: GetScript('OnClick') failed for checkbox:", result)
            end
        end
        checkbox:SetScript("OnClick", function(self)
            if originalOnClick then originalOnClick(self) end
            showCompleted = NormalizeCheckButtonChecked(self)
            -- Save to DB
            if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.plansShowCompleted = showCompleted
            end
            -- Refresh UI to apply filter
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
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
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText((ns.L and ns.L["SHOW_COMPLETED"]) or "Show Completed", 1, 1, 1)
            GameTooltip:AddLine((ns.L and ns.L["SHOW_COMPLETED_HELP"]) or "To-Do List and Weekly Progress: unchecked = plans still in progress; checked = completed plans only. Browse tabs: unchecked = uncollected browse (optionally only To-Do items if Show Planned is on); checked = include collected To-Do entries.", 0.75, 0.75, 0.75, true)
            GameTooltip:Show()
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
            GameTooltip:Hide()
        end)
        
        -- "Show Planned" only affects browse subtabs, but the control stays visible (dimmed on To-Do / Weekly Progress).
        local plannedBrowseLocked = (currentCategory == "active" or currentCategory == "daily_tasks")
        local plannedCheckbox = CreateThemedCheckbox(titleCard, showPlanned)
        if plannedCheckbox then
            if plannedCheckbox.innerDot then
                plannedCheckbox.innerDot:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            end
            plannedCheckbox:SetPoint("RIGHT", checkboxLabel, "LEFT", -16, 0)

            local plannedLabel = FontManager:CreateFontString(titleCard, "body", "OVERLAY")
            plannedLabel:SetPoint("RIGHT", plannedCheckbox, "LEFT", -hdrToolbarGap, 0)
            plannedLabel:SetText((ns.L and ns.L["SHOW_PLANNED"]) or "Show Planned")
            plannedLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])

            local function ApplyPlannedBrowseLockVisuals()
                local dim = plannedBrowseLocked and 0.42 or 1
                plannedCheckbox:SetAlpha(dim)
                plannedLabel:SetAlpha(dim)
                plannedCheckbox:EnableMouse(not plannedBrowseLocked)
            end
            ApplyPlannedBrowseLockVisuals()

            local origPlannedOnClick = nil
            if plannedCheckbox.GetScript then
                local ok2, res2 = pcall(function() return plannedCheckbox:GetScript("OnClick") end)
                if ok2 then origPlannedOnClick = res2 end
            end
            plannedCheckbox:SetScript("OnClick", function(self)
                if plannedBrowseLocked then return end
                if origPlannedOnClick then origPlannedOnClick(self) end
                showPlanned = NormalizeCheckButtonChecked(self)
                if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile then
                    WarbandNexus.db.profile.plansShowPlanned = showPlanned
                end
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
            end)

            local origPlannedEnter = nil
            if plannedCheckbox.GetScript then
                local ok3, res3 = pcall(function() return plannedCheckbox:GetScript("OnEnter") end)
                if ok3 then origPlannedEnter = res3 end
            end
            plannedCheckbox:SetScript("OnEnter", function(self)
                if origPlannedEnter then origPlannedEnter(self) end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText((ns.L and ns.L["SHOW_PLANNED"]) or "Show Planned", 1, 1, 1)
                if plannedBrowseLocked then
                    GameTooltip:AddLine((ns.L and ns.L["SHOW_PLANNED_DISABLED_HERE"]) or "Not used on To-Do List or Weekly Progress. Open Mounts, Pets, Toys, or another browse tab to use this filter.", 0.72, 0.72, 0.76, true)
                else
                    GameTooltip:AddLine((ns.L and ns.L["SHOW_PLANNED_HELP"]) or "Browse tabs only: limit the list to items on your To-Do. Pair with Show Completed for still-needed vs already-finished planned items. Hidden on To-Do List and Weekly Progress.", 0.75, 0.75, 0.75, true)
                end
                GameTooltip:Show()
            end)

            local origPlannedLeave = nil
            if plannedCheckbox.GetScript then
                local ok4, res4 = pcall(function() return plannedCheckbox:GetScript("OnLeave") end)
                if ok4 then origPlannedLeave = res4 end
            end
            plannedCheckbox:SetScript("OnLeave", function(self)
                if origPlannedLeave then origPlannedLeave(self) end
                GameTooltip:Hide()
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
        
        -- WN_PLANS_UPDATED: handled by UI.lua SchedulePopulateContent (debounced).
        -- Registering here caused double rebuild (immediate redraw + debounced PopulateContent).
        
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
                        WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
                    end
                end)
            end)
            
            -- Collection scan complete (final refresh)
            -- COLLECTION_SCAN_COMPLETE and COLLECTION_UPDATED refresh are centralized in UI.lua.
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
    for i = 1, #CATEGORIES do
        local cat = CATEGORIES[i]
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
    
    for i = 1, #CATEGORIES do
        local cat = CATEGORIES[i]
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
            ns._sessionPlansCategory = cat.key
            searchText = ""
            
            -- Defer UI refresh to next frame to prevent button freeze
            C_Timer.After(0.05, function()
                if not WarbandNexus or not WarbandNexus.SendMessage then return end
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
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
        if FontManager then
            local p = FontManager:GetFontFace()
            local s = FontManager:GetFontSize("body")
            local f = FontManager:GetAAFlags()
            pcall(searchInput.SetFont, searchInput, p, s, f)
        end
        searchInput:SetTextColor(1, 1, 1, 1)
        searchInput:SetAutoFocus(false)
        searchInput:SetMaxLetters(50)
        local searchPlaceholder = (ns.L and ns.L["SEARCH_PLANS"]) or "Search plans..."
        searchInput.Instructions = searchInput:CreateFontString(nil, "ARTWORK")
        if FontManager then
            FontManager:ApplyFont(searchInput.Instructions, "body")
        end
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
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
        end)
        searchInput:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end  -- Ignore programmatic SetText calls
            local text = self:GetText() or ""
            if text and issecretvalue and issecretvalue(text) then
                ns._plansActiveSearch = nil
                if self.Instructions then self.Instructions:Show() end
                return
            end
            ns._plansActiveSearch = (text ~= "") and text or nil
            -- Show/hide placeholder
            if self.Instructions then
                if text ~= "" then self.Instructions:Hide() else self.Instructions:Show() end
            end
            if WarbandNexus._plansSearchTimer then
                WarbandNexus._plansSearchTimer:Cancel()
            end
            WarbandNexus._plansSearchTimer = C_Timer.NewTimer(0.3, function()
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
            end)
        end)
        searchBar:EnableMouse(true)
        searchBar:SetScript("OnMouseDown", function() searchInput:SetFocus() end)
        searchBar:Show()

        local searchH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.SEARCH_BOX_HEIGHT) or 32
        yOffset = yOffset + searchH + GetLayout().afterElement
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
            return format("%d %s %d %s", days, days == 1 and Day or Days, hours, hours == 1 and Hour or Hours)
        end
        return format("%d %s", days, days == 1 and Day or Days)
    elseif minutes >= 60 then
        local hours = math.floor(minutes / 60)
        local mins = minutes % 60
        if mins > 0 then
            return format("%d %s %d %s", hours, hours == 1 and Hour or Hours, mins, mins == 1 and Minute or Minutes)
        end
        return format("%d %s", hours, hours == 1 and Hour or Hours)
    end
    return format("%d %s", minutes, minutes == 1 and Minute or Minutes)
end

local EVENT_GROUP_NAMES = {
    soiree     = (ns.L and ns.L["EVENT_GROUP_SOIREE"]) or "Saltheril's Soiree",
    abundance  = (ns.L and ns.L["EVENT_GROUP_ABUNDANCE"]) or "Abundance",
    haranir    = (ns.L and ns.L["EVENT_GROUP_HARANIR"]) or "Legends of the Haranir",
    stormarion = (ns.L and ns.L["EVENT_GROUP_STORMARION"]) or "Stormarion Assault",
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
                text = format(
                    (ns.L and ns.L["QUEST_PROGRESS_FORMAT"]) or "Progress: %d/%d (%d%%)",
                    quest.progress.totalFulfilled or 0,
                    quest.progress.totalRequired or 0,
                    pct
                ),
                color = pct >= 100 and {0.27, 1, 0.27} or {1, 0.82, 0.2},
            }
        end
        if quest.timeLeft and quest.timeLeft > 0 then
            local timeColor = quest.timeLeft < 60 and {1, 0.3, 0.3} or {0.7, 0.7, 0.7}
            lines[#lines + 1] = {
                text = format(
                    (ns.L and ns.L["QUEST_TIME_REMAINING_FORMAT"]) or "%s remaining",
                    FormatTimeLeft(quest.timeLeft)
                ),
                color = timeColor
            }
        end
        if quest.isComplete then
            lines[#lines + 1] = { text = "|cff44ff44" .. ((ns.L and ns.L["COMPLETE_LABEL"]) or "Complete") .. "|r", color = {0.27, 1, 0.27} }
        elseif quest.isLocked then
            lines[#lines + 1] = { text = "|cffff9933" .. ((ns.L and ns.L["LOCKED_WORLD_QUESTS"]) or "Locked — complete World Quests to unlock") .. "|r", color = {1, 0.6, 0.2} }
        end
        if quest.questID then
            lines[#lines + 1] = { text = format((ns.L and ns.L["QUEST_ID_FORMAT"]) or "Quest ID: %s", quest.questID), color = {0.5, 0.5, 0.5} }
            lines[#lines + 1] = { text = (ns.L and ns.L["CLICK_FOR_WOWHEAD_LINK"]) or "Click for Wowhead link", color = {0.5, 0.4, 0.7} }
        end

        if ns.TooltipService and ns.TooltipService.Show then
            ns.TooltipService:Show(self, {
                type = "custom",
                title = quest.title or ((ns.L and ns.L["SOURCE_TYPE_QUEST"]) or "Quest"),
                icon = false,
                anchor = "ANCHOR_RIGHT",
                lines = lines,
            })
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(quest.title or ((ns.L and ns.L["SOURCE_TYPE_QUEST"]) or "Quest"), 1, 1, 1)
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
    if quest.questID and quest.questID > 0 then
        frame:SetScript("OnMouseDown", function(self)
            if ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                ns.UI.Factory:ShowWowheadCopyURL("quest", quest.questID, self)
            end
        end)
    end
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

    if resetBar._weeklyResetTicker then
        resetBar._weeklyResetTicker:Cancel()
        resetBar._weeklyResetTicker = nil
    end
    resetBar._weeklyResetTicker = C_Timer.NewTicker(60, function()
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
    end)
    resetBar:SetScript("OnHide", function(self2)
        if self2._weeklyResetTicker then
            self2._weeklyResetTicker:Cancel()
            self2._weeklyResetTicker = nil
        end
    end)

    resetBar:Show()
    yOffset = yOffset + resetBarH + 6

    -- ===== PER-CHARACTER DETAIL SECTIONS (accordion: character + categories) =====
    local Factory = ns.UI.Factory
    local SECTION_COLLAPSE_H = (GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT) or 36
    local sectionSpacing = (GetLayout().SECTION_SPACING) or 8
    local innerW = math.max(1, width - 20)
    local STATS_H = 28
    local scrollTop = yOffset
    local weeklyChainTail = nil
    local totalBlockH = 0

    if parent._weeklyScrollFixTimer then
        parent._weeklyScrollFixTimer:Cancel()
        parent._weeklyScrollFixTimer = nil
    end

    --- Sum stacked rows (stats strip + category wraps) so inner accordion tweens update outer height.
    local function ReflowWeeklyProgressCharSectionBody(body)
        if not body or not body._weeklyRowList then return end
        local list = body._weeklyRowList
        local sp = body._weeklySectionSpacing or sectionSpacing
        local h = (list[1] and list[1]:GetHeight()) or STATS_H
        for ri = 2, #list do
            local rowFr = list[ri]
            if rowFr then
                h = h + sp + (rowFr:GetHeight() or 0.1)
            end
        end
        h = math.max(0.1, h + 6)
        body._wnAccordionFullH = h
        local wrap = body._weeklyParentWrap
        local hdrH = (wrap and wrap._weeklyHeaderH) or SECTION_COLLAPSE_H
        if body:IsShown() then
            body:SetHeight(h)
            if wrap then
                wrap:SetHeight(hdrH + h)
            end
        end
    end

    local function ScheduleWeeklyProgressScrollSync()
        if not parent then return end
        if parent._weeklyScrollFixTimer then
            parent._weeklyScrollFixTimer:Cancel()
        end
        parent._weeklyScrollFixTimer = C_Timer.NewTimer(0.06, function()
            parent._weeklyScrollFixTimer = nil
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            if mf and mf.currentTab == "plans" then
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, {
                    tab = "plans",
                    skipCooldown = true,
                    instantPopulate = true,
                })
            end
        end)
    end

    local function WeeklyAccordionToggleNoop() end

    for pi = 1, #filteredPlans do
        local plan = filteredPlans[pi]
        local classColor = RAID_CLASS_COLORS[plan.characterClass or "PRIEST"] or {r = 1, g = 1, b = 1}

        local totalAll, completedAll = 0, 0
        for ci = 1, #CATEGORIES do
            local catInfo = CATEGORIES[ci]
            if plan.questTypes and plan.questTypes[catInfo.key] then
                local c, t = GetCategoryStats(plan, catInfo.key)
                completedAll = completedAll + c
                totalAll = totalAll + t
            end
        end

        if weeklyChainTail then
            totalBlockH = totalBlockH + sectionSpacing
        end

        local charWrap = Factory:CreateContainer(parent, innerW, SECTION_COLLAPSE_H + 0.1, false)
        if charWrap.SetClipsChildren then
            charWrap:SetClipsChildren(true)
        end
        charWrap:ClearAllPoints()
        ChainSectionFrameBelow(parent, charWrap, weeklyChainTail, 10, weeklyChainTail and sectionSpacing or nil, weeklyChainTail and nil or scrollTop)

        local realmHdr = plan.characterRealm or ""
        if realmHdr ~= "" and ns.Utilities and ns.Utilities.FormatRealmName then
            realmHdr = ns.Utilities:FormatRealmName(realmHdr)
        end
        local charTitlePlain = format(
            "|cff%02x%02x%02x%s|r |cff888888-%s|r",
            classColor.r * 255, classColor.g * 255, classColor.b * 255,
            plan.characterName or "Unknown",
            realmHdr
        )

        local charGroupKey = "weekly_char_" .. tostring(plan.id)
        local charExpanded = (expandedGroups[charGroupKey] ~= false)

        local charSectionBody
        local charHeader, charHdrExpandIcon, _, charHdrTitleFs = CreateCollapsibleHeader(
            charWrap,
            charTitlePlain,
            charGroupKey,
            charExpanded,
            WeeklyAccordionToggleNoop,
            nil,
            true,
            0,
            true,
            BuildAccordionVisualOpts({
                wrapFrame = charWrap,
                bodyGetter = function() return charSectionBody end,
                headerHeight = SECTION_COLLAPSE_H,
                hideOnCollapse = true,
                deferOnToggleUntilComplete = true,
                accordionClipChildren = false,
                persistFn = function(exp)
                    expandedGroups[charGroupKey] = exp
                end,
                onComplete = function()
                    ReflowWeeklyProgressCharSectionBody(charSectionBody)
                    ScheduleWeeklyProgressScrollSync()
                end,
            })
        )
        charHeader:SetPoint("TOPLEFT", charWrap, "TOPLEFT", 0, 0)
        charHeader:SetWidth(innerW)

        if charHeader._wnSectionStripe then
            charHeader._wnSectionStripe:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.9)
        end
        if charHdrExpandIcon and charHdrExpandIcon._wnCollapseTex then
            local r = math.min(1, classColor.r * 1.5)
            local g = math.min(1, classColor.g * 1.5)
            local b = math.min(1, classColor.b * 1.5)
            charHdrExpandIcon._wnCollapseTex:SetVertexColor(r, g, b)
            charHdrExpandIcon._wnCollapseVertexColor = { r, g, b, 1 }
        end

        local removeBtn = Factory:CreateButton(charHeader, 24, 24, true)
        removeBtn:SetPoint("RIGHT", -8, 0)
        removeBtn:SetFrameLevel((charHeader:GetFrameLevel() or 0) + 5)
        removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        removeBtn:SetScript("OnClick", function()
            self:RemovePlan(plan.id)
        end)

        local totalFs = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        totalFs:SetPoint("RIGHT", removeBtn, "LEFT", -6, 0)
        local totalColor = (totalAll > 0 and completedAll == totalAll) and "|cff44ff44" or "|cffffcc00"
        totalFs:SetText(totalColor .. completedAll .. "/" .. totalAll .. "|r")

        if charHdrTitleFs then
            charHdrTitleFs:SetJustifyH("LEFT")
            charHdrTitleFs:SetWordWrap(false)
            charHdrTitleFs:SetMaxLines(1)
            charHdrTitleFs:SetPoint("RIGHT", totalFs, "LEFT", -10, 0)
        end

        charSectionBody = Factory:CreateContainer(charWrap, innerW, 0.1, false)
        charSectionBody:ClearAllPoints()
        charSectionBody:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, 0)
        charSectionBody:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)

        local statsStrip = Factory:CreateContainer(charSectionBody, innerW, STATS_H, false)
        statsStrip:SetPoint("TOPLEFT", charSectionBody, "TOPLEFT", 0, 0)
        if statsStrip.SetClipsChildren then
            statsStrip:SetClipsChildren(true)
        end

        local catX = 8
        for ci = 1, #CATEGORIES do
            local catInfo = CATEGORIES[ci]
            if plan.questTypes and plan.questTypes[catInfo.key] then
                local display = CAT_DISPLAY[catInfo.key] or {}
                local catColor = display.color or {0.8, 0.8, 0.8}
                local catName = display.name and display.name() or catInfo.key
                local c, t = GetCategoryStats(plan, catInfo.key)
                if t > 0 then
                    local catFs = FontManager:CreateFontString(statsStrip, "small", "OVERLAY")
                    catFs:SetPoint("LEFT", statsStrip, "LEFT", catX, 0)
                    local cColor = (c == t) and "|cff44ff44" or format("|cff%02x%02x%02x", catColor[1] * 255, catColor[2] * 255, catColor[3] * 255)
                    catFs:SetText(cColor .. catName .. " " .. c .. "/" .. t .. "|r")
                    catX = catX + catFs:GetStringWidth() + 12
                end
            end
        end

        local catChainTail = statsStrip
        local weeklyRowList = { statsStrip }

        for ci = 1, #CATEGORIES do
            local catInfo = CATEGORIES[ci]
            local catKey = catInfo.key
            if plan.questTypes and plan.questTypes[catKey] then
                local questList = (plan.quests and plan.quests[catKey]) or {}
                local display = CAT_DISPLAY[catKey] or {}
                local catColor = display.color or {0.8, 0.8, 0.8}
                local catName = display.name and display.name() or catKey

                local completed, total = GetCategoryStats(plan, catKey)
                local groupKey = "dq_" .. tostring(plan.id) .. "_" .. catKey
                local isExpanded = (expandedGroups[groupKey] ~= false)

                local SECTION_HDR_H = (GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT) or 36
                local catAtlas = (display and display.atlas) or "questlog-questtypeicon-weekly"
                local catTitleHex = format(
                    "|cff%02x%02x%02x%s|r",
                    math.floor(catColor[1] * 255),
                    math.floor(catColor[2] * 255),
                    math.floor(catColor[3] * 255),
                    catName
                )

                local catWrap = Factory:CreateContainer(charSectionBody, innerW, SECTION_HDR_H + 0.1, false)
                if catWrap.SetClipsChildren then
                    catWrap:SetClipsChildren(true)
                end
                catWrap:ClearAllPoints()
                ChainSectionFrameBelow(charSectionBody, catWrap, catChainTail, 0, sectionSpacing, nil)

                weeklyRowList[#weeklyRowList + 1] = catWrap

                local sectionBody
                local catHeader, hdrExpandIcon, hdrCategoryIcon, catHdrTitleFs = CreateCollapsibleHeader(
                    catWrap,
                    catTitleHex,
                    groupKey,
                    isExpanded,
                    WeeklyAccordionToggleNoop,
                    catAtlas,
                    true,
                    0,
                    nil,
                    BuildAccordionVisualOpts({
                        wrapFrame = catWrap,
                        bodyGetter = function() return sectionBody end,
                        headerHeight = SECTION_HDR_H,
                        hideOnCollapse = true,
                        deferOnToggleUntilComplete = true,
                        accordionClipChildren = false,
                        persistFn = function(exp)
                            expandedGroups[groupKey] = exp
                        end,
                        onUpdate = function()
                            ReflowWeeklyProgressCharSectionBody(charSectionBody)
                        end,
                        onComplete = function()
                            ReflowWeeklyProgressCharSectionBody(charSectionBody)
                            ScheduleWeeklyProgressScrollSync()
                        end,
                    })
                )
                catHeader:SetPoint("TOPLEFT", catWrap, "TOPLEFT", 0, 0)
                catHeader:SetWidth(innerW)
                catHeader:SetHeight(SECTION_HDR_H)

                sectionBody = Factory:CreateContainer(catWrap, innerW, 0.1, false)
                sectionBody:ClearAllPoints()
                sectionBody:SetPoint("TOPLEFT", catHeader, "BOTTOMLEFT", 0, 0)
                sectionBody:SetPoint("TOPRIGHT", catHeader, "BOTTOMRIGHT", 0, 0)

                if catHeader._wnSectionStripe then
                    catHeader._wnSectionStripe:SetColorTexture(catColor[1], catColor[2], catColor[3], 0.9)
                end
                if hdrExpandIcon and hdrExpandIcon._wnCollapseTex then
                    local r2 = math.min(1, catColor[1] * 1.5)
                    local g2 = math.min(1, catColor[2] * 1.5)
                    local b2 = math.min(1, catColor[3] * 1.5)
                    hdrExpandIcon._wnCollapseTex:SetVertexColor(r2, g2, b2)
                    hdrExpandIcon._wnCollapseVertexColor = { r2, g2, b2, 1 }
                end
                if hdrCategoryIcon then
                    hdrCategoryIcon:SetVertexColor(catColor[1], catColor[2], catColor[3])
                end

                local countHdrFs = FontManager:CreateFontString(catHeader, "body", "OVERLAY")
                countHdrFs:SetPoint("RIGHT", -14, 0)
                local countColorHdr = (completed == total and total > 0) and "|cff44ff44" or "|cffffffff"
                countHdrFs:SetText(countColorHdr .. completed .. "/" .. total .. "|r")

                if catHdrTitleFs then
                    catHdrTitleFs:SetJustifyH("LEFT")
                    catHdrTitleFs:SetWordWrap(false)
                    catHdrTitleFs:SetMaxLines(1)
                    catHdrTitleFs:SetPoint("RIGHT", countHdrFs, "LEFT", -10, 0)
                end

                local rowY = 4
                if #questList == 0 then
                    local emptyRow
                    emptyRow, rowY = Factory:CreateDataRow(sectionBody, rowY, 1, ROW_H)
                    local emptyIcon = emptyRow:CreateTexture(nil, "ARTWORK")
                    emptyIcon:SetSize(14, 14)
                    emptyIcon:SetPoint("LEFT", 14, 0)
                    emptyIcon:SetAtlas("Objective-Nub", false)
                    emptyIcon:SetVertexColor(0.4, 0.4, 0.4)
                    local emptyFs = FontManager:CreateFontString(emptyRow, "body", "OVERLAY")
                    emptyFs:SetPoint("LEFT", 32, 0)
                    emptyFs:SetTextColor(0.5, 0.5, 0.5)
                    emptyFs:SetText((ns.L and ns.L["NO_ACTIVE_CONTENT"]) or "No active content this week")
                else
                    for qi = 1, #questList do
                        local quest = questList[qi]
                        local hasObjectives = (quest.objectives and #quest.objectives > 0) or false
                        local isSub = quest.isSubQuest
                        local leftIndent = isSub and 26 or 14
                        local iconSize = isSub and 12 or 14
                        local nObj = hasObjectives and quest.objectives and #quest.objectives or 0
                        local rowH = ROW_H
                        if hasObjectives and nObj > 0 then
                            rowH = math.max(ROW_H, 14 + 16 * nObj + 18)
                        end

                        local row
                        row, rowY = Factory:CreateDataRow(sectionBody, rowY, qi, rowH)
                        row:EnableMouse(true)

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

                                local objText = obj.text or format((ns.L and ns.L["OBJECTIVE_INDEX_FORMAT"]) or "Objective %d", oi)
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
                                progFs:SetText(format("%s%d/%d|r", progColor, obj.numFulfilled, obj.numRequired))
                            end

                            if quest.zone and quest.zone ~= "" then
                                local zoneFs = FontManager:CreateFontString(row, "small", "OVERLAY")
                                zoneFs:SetPoint("TOPRIGHT", -14, -6)
                                zoneFs:SetJustifyH("RIGHT")
                                zoneFs:SetText("|cff888888" .. quest.zone .. "|r")
                            end
                        else
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

                local sectionBodyH = rowY + 4
                sectionBody._wnAccordionFullH = math.max(0.1, sectionBodyH)
                if isExpanded then
                    sectionBody:Show()
                    sectionBody:SetHeight(math.max(0.1, sectionBodyH))
                else
                    sectionBody:Hide()
                    sectionBody:SetHeight(0.1)
                end

                local catWrapH = SECTION_HDR_H + (isExpanded and sectionBodyH or 0.1)
                catWrap:SetHeight(catWrapH)
                catChainTail = catWrap
            end
        end

        charSectionBody._weeklyRowList = weeklyRowList
        charSectionBody._weeklySectionSpacing = sectionSpacing
        charSectionBody._weeklyParentWrap = charWrap
        charWrap._weeklyHeaderH = SECTION_COLLAPSE_H

        if charExpanded then
            charSectionBody:Show()
            charSectionBody:SetAlpha(1)
        else
            charSectionBody:Hide()
            charSectionBody:SetHeight(0.1)
        end

        ReflowWeeklyProgressCharSectionBody(charSectionBody)

        if charExpanded then
            local fullH = charSectionBody._wnAccordionFullH or 0.1
            charSectionBody:SetHeight(math.max(0.1, fullH))
            charWrap:SetHeight(SECTION_COLLAPSE_H + charSectionBody:GetHeight())
        else
            charSectionBody:Hide()
            charSectionBody:SetHeight(0.1)
            charWrap:SetHeight(SECTION_COLLAPSE_H + 0.1)
        end

        local charTotalH = charWrap:GetHeight()
        totalBlockH = totalBlockH + charTotalH
        weeklyChainTail = charWrap
    end

    return scrollTop + totalBlockH + 10
end

function WarbandNexus:DrawActivePlans(parent, yOffset, width, category)
    local plans
    if category == "daily_tasks" then
        plans = {}
        if self.db and self.db.global then
            if self.db.global.plans then
                local p = self.db.global.plans
                for i = 1, #p do
                    local plan = p[i]
                    if plan.type == "daily_quests" then
                        plans[#plans + 1] = plan
                    end
                end
            end
            if self.db.global.customPlans then
                local c = self.db.global.customPlans
                for i = 1, #c do
                    local plan = c[i]
                    if plan.type == "daily_quests" then
                        plans[#plans + 1] = plan
                    end
                end
            end
        end
    else
        plans = self:GetActivePlans()
    end
    
    -- Apply search filter (My Plans global search, skip for daily_tasks)
    if category ~= "daily_tasks" then
        local activeSearch = ns._plansActiveSearch
        if activeSearch and not (issecretvalue and issecretvalue(activeSearch)) and activeSearch ~= "" then
            local query = activeSearch:lower()
            local searchFiltered = {}
            for i = 1, #plans do
                local plan = plans[i]
                local resolvedName = (WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name or ""
                local name = SafeLower(resolvedName)
                local source = SafeLower(plan.resolvedSource or plan.source or "")
                local ptype = SafeLower(plan.type or "")
                if name:find(query, 1, true) or source:find(query, 1, true) or ptype:find(query, 1, true) then
                    searchFiltered[#searchFiltered + 1] = plan
                end
            end
            plans = searchFiltered
        end
    end

    -- Sort plans: Weekly Progress (daily quests) first, then Great Vault, then others
    local typePriority = { daily_quests = 1, weekly_vault = 2 }
    table.sort(plans, function(a, b)
        local pa = typePriority[a.type] or 99
        local pb = typePriority[b.type] or 99
        if pa ~= pb then return pa < pb end
        local aID = tonumber(a.id) or 0
        local bID = tonumber(b.id) or 0
        return aID < bID
    end)

    -- To-Do List & Weekly Progress: list is already only saved plans. Show Planned is ignored here (browse only).
    -- Show Completed off = in-progress plans only; on = completed plans only.
    local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local showCompletedNow = ProfileBool(profile, "plansShowCompleted", false)
    local filteredPlans = {}
    for i = 1, #plans do
        local plan = plans[i]
        local isComplete = self:IsActivePlanComplete(plan)
        local include = (showCompletedNow and isComplete) or ((not showCompletedNow) and (not isComplete))
        if include then
            filteredPlans[#filteredPlans + 1] = plan
        end
    end
    plans = filteredPlans

    -- 2-column layout: count of "regular" plans before each index (excludes weekly_vault / daily_quests).
    -- Precompute O(n) instead of O(n²) inner loop per card.
    local regularCountBefore = {}
    do
        local rc = 0
        for idx = 1, #plans do
            regularCountBefore[idx] = rc
            local pt = plans[idx].type
            if pt ~= "weekly_vault" and pt ~= "daily_quests" then
                rc = rc + 1
            end
        end
    end

    if category == "daily_tasks" then
        parent._plansCardLayoutManager = nil
        return self:DrawDailyTasksView(parent, yOffset, width, plans)
    end
    
    if #plans == 0 then
        parent._plansCardLayoutManager = nil
        -- Empty state card using standardized factory
        local _, height = CreateEmptyStateCard(parent, "plans", yOffset)
        return yOffset + height + 10
    end
    
    -- === 2-COLUMN CARD GRID (same column math + chrome as Browse — ns.UI_PlansCardGridColumnWidth) ===
    local PCM = ns.UI_PLANS_CARD_METRICS
    local cardSpacing = (PCM and PCM.gridSpacing) or 8
    local cardWidth = ns.UI_PlansCardGridColumnWidth and ns.UI_PlansCardGridColumnWidth(width)
        or math.max(100, (width - cardSpacing) / 2)
    local todoHeaderH = ns.UI_PlansTodoExpandableHeaderHeight and ns.UI_PlansTodoExpandableHeaderHeight(width) or 60
    
    -- Initialize CardLayoutManager for dynamic card positioning
    local layoutManager = CardLayoutManager:Create(parent, 2, cardSpacing, yOffset)
    -- Always point at the active layout: PopulateContent rebuilds cards but OnSizeChanged is only hooked once;
    -- a stale closure capture would RefreshLayout the wrong (old) instance and corrupt positions after resize/scroll.
    parent._plansCardLayoutManager = layoutManager

    -- Resize: defer layout refresh until resize ends (no continuous render during drag)
    if not parent._layoutManagerResizeHandler then
        local layoutResizeTimer = nil
        parent:SetScript("OnSizeChanged", function(resizeParent)
            if layoutResizeTimer then
                layoutResizeTimer:Cancel()
            end
            layoutResizeTimer = C_Timer.NewTimer(0.15, function()
                layoutResizeTimer = nil
                local lm = resizeParent and resizeParent._plansCardLayoutManager
                if lm then
                    CardLayoutManager:RefreshLayout(lm)
                end
            end)
        end)
        parent._layoutManagerResizeHandler = true
    end
    
    for i = 1, #plans do
        local plan = plans[i]
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
            -- === REGULAR PLANS (2-column expandable rows, mirrors the floating tracker) ===
            local listCardWidth = cardWidth
            local col = (regularCountBefore[i] or 0) % 2

            local PCF = ns.UI_PlanCardFactory
            local typeAtlas = PCF and PCF.TYPE_ICONS and PCF.TYPE_ICONS[plan.type]
            local resolvedName = (self.GetResolvedPlanName and self:GetResolvedPlanName(plan)) or plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
            local resolvedIcon = (self.GetResolvedPlanIcon and self:GetResolvedPlanIcon(plan)) or plan.iconAtlas or plan.icon
            local iconIsAtlas = false
            if plan.iconAtlas then iconIsAtlas = true
            elseif plan.type == "custom" and plan.icon and plan.icon ~= "" then iconIsAtlas = true
            elseif type(resolvedIcon) == "string" and ns.Utilities and ns.Utilities.IsAtlasName and ns.Utilities:IsAtlasName(resolvedIcon) then iconIsAtlas = true
            end
            if not resolvedIcon or resolvedIcon == "" then resolvedIcon = "Interface\\Icons\\INV_Misc_QuestionMark" end

            local isExpanded = expandedPlans[plan.id] or false

            -- Achievement title: points from plan row, session cache after first expand, or API only when expanded at draw time.
            local titleStr = FormatTextNumbers(resolvedName)
            local achievementOnExpandPopulate = nil
            if plan.type == "achievement" and plan.achievementID then
                local achID = plan.achievementID
                local sess = PlansAchievementSessionCache()[achID]
                local pts = tonumber(plan.points) or 0
                if pts <= 0 and sess then
                    pts = tonumber(sess.points) or 0
                end
                if isExpanded and pts <= 0 then
                    local entry = EnsurePlansAchievementExpandCache(achID)
                    pts = tonumber(entry and entry.points) or 0
                end
                if pts > 0 then
                    titleStr = titleStr .. format(" - |cffffd700(%d pts)|r", pts)
                end
                if not isExpanded then
                    achievementOnExpandPopulate = function(data, row)
                        local entry = EnsurePlansAchievementExpandCache(achID)
                        data.information = entry.information
                        data.criteria = entry.criteriaText
                        data.criteriaData = entry.criteriaItems
                        data.criteriaShowHeader = true
                        if row and row.titleText then
                            local ptn = tonumber(plan.points) or 0
                            if ptn <= 0 then ptn = tonumber(entry.points) or 0 end
                            local ts = FormatTextNumbers(resolvedName)
                            if ptn > 0 then
                                ts = ts .. format(" - |cffffd700(%d pts)|r", ptn)
                            end
                            row.titleText:SetText("|cffffffff" .. ts .. "|r")
                        end
                        if row and row.SyncHeaderToTitle then
                            row:SyncHeaderToTitle()
                        end
                    end
                end
            end

            -- Build expanded body: information + criteria (achievement: APIs only when expanded or via onExpandPopulate)
            local information, criteriaItems, criteriaHeader, criteriaText
            if plan.type == "achievement" and plan.achievementID then
                criteriaHeader = true
                if isExpanded then
                    local entry = EnsurePlansAchievementExpandCache(plan.achievementID)
                    information = entry.information
                    criteriaText = entry.criteriaText
                    criteriaItems = entry.criteriaItems
                end
            else
                if plan.type == "custom" then
                    local d = plan.description or plan.note or ""
                    if d ~= "" and d ~= "Custom plan" then information = d end
                end
                criteriaItems = ns.UI_BuildPlanCriteriaItems and ns.UI_BuildPlanCriteriaItems(plan) or {}
                criteriaHeader = false
            end

            -- Right-side actions (R→L: Delete, Alert, Complete?, Tries). Sizes match type badge (todoTypeBadgeSize).
            local typeBadgeSz = (PCM and PCM.todoTypeBadgeSize) or 24
            local ACTION_SIZE, ACTION_GAP = typeBadgeSz, 4
            local tryW = 72
            local tryCountTypes = { mount = "mountID", pet = "speciesID", toy = "itemID", illusion = "sourceID" }
            local idKey = tryCountTypes[plan.type]
            local collectibleID = idKey and (plan[idKey] or (plan.type == "illusion" and plan.illusionID))
            local hasTry = collectibleID and ns.UI.Factory and ns.UI.Factory.CreateTryCountClickable
                and self.ShouldShowTryCountInUI and self:ShouldShowTryCountInUI(plan.type, collectibleID)
            local titleRightInset = 6
            titleRightInset = titleRightInset + ACTION_SIZE + ACTION_GAP -- delete (rightmost)
            titleRightInset = titleRightInset + ACTION_SIZE + ACTION_GAP -- alert
            if plan.type == "custom" then titleRightInset = titleRightInset + ACTION_SIZE + ACTION_GAP end
            if hasTry then titleRightInset = titleRightInset + tryW + ACTION_GAP end

            local rowData = {
                icon = resolvedIcon,
                iconIsAtlas = iconIsAtlas,
                iconSize = (PCM and PCM.todoIconSize) or 41,
                typeAtlas = typeAtlas,
                typeBadgeSize = (PCM and PCM.todoTypeBadgeSize) or 24,
                title = titleStr,
                information = information,
                criteria = criteriaText,
                criteriaData = criteriaItems,
                criteriaColumns = 2,
                criteriaShowHeader = criteriaHeader,
                titleRightInset = titleRightInset,
                -- Per-frame reflow: keep the rest of the grid breathing with this row's tween.
                onAccordionResize = function(rowFrame, currentH)
                    CardLayoutManager:UpdateCardHeight(rowFrame, currentH)
                end,
                onExpandPopulate = achievementOnExpandPopulate,
            }

            local row = CreateExpandableRow(parent, listCardWidth, todoHeaderH, rowData, isExpanded, function(expanded)
                -- Persist state only — the layout has been kept in sync per-frame already.
                expandedPlans[plan.id] = expanded
            end)

            row:SetWidth(listCardWidth)
            CardLayoutManager:AddCard(layoutManager, row, col, row:GetHeight())

            if ApplyVisuals then
                local borderColor = { COLORS.accent[1] * 0.8, COLORS.accent[2] * 0.8, COLORS.accent[3] * 0.8, 0.4 }
                ApplyVisuals(row, {0.08, 0.08, 0.10, 1}, borderColor)
            end

            -- Header right-side actions (Delete + optional Complete) sit above the headerFrame's
            -- expand-toggle handler so clicks reach the action button, not the toggle.
            local rightOffset = 6
            local function makeAction(normalTex, highlightTex, onClick, tooltipKey, tooltipFallback)
                local btn = ns.UI.Factory:CreateButton(row.headerFrame, ACTION_SIZE, ACTION_SIZE, true)
                btn:SetPoint("RIGHT", row.headerFrame, "RIGHT", -rightOffset, 0)
                btn:SetFrameLevel(row.headerFrame:GetFrameLevel() + 10)
                btn:SetNormalTexture(normalTex)
                btn:SetHighlightTexture(highlightTex)
                btn:SetScript("OnMouseDown", function() end)
                btn:RegisterForClicks("AnyUp")
                btn:SetScript("OnClick", onClick)
                btn:SetScript("OnEnter", function(b)
                    ns.TooltipService:Show(b, {
                        type = "custom",
                        title = (ns.L and ns.L[tooltipKey]) or tooltipFallback,
                        icon = false, anchor = "ANCHOR_TOP", lines = {},
                    })
                end)
                btn:SetScript("OnLeave", function() ns.TooltipService:Hide() end)
                rightOffset = rightOffset + ACTION_SIZE + ACTION_GAP
                return btn
            end

            makeAction(
                "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
                "Interface\\Buttons\\UI-GroupLoot-Pass-Highlight",
                function() if plan.id then self:RemovePlan(plan.id) end end,
                "PLAN_ACTION_DELETE", "Delete the Plan"
            )

            if PlanCardFactory.CreateReminderAlertButton then
                local remBtn = PlanCardFactory.CreateReminderAlertButton(row.headerFrame, plan)
                if remBtn then
                    remBtn:SetPoint("RIGHT", row.headerFrame, "RIGHT", -rightOffset, 0)
                    remBtn:SetFrameLevel((row.headerFrame:GetFrameLevel() or 0) + 12)
                    rightOffset = rightOffset + ACTION_SIZE + ACTION_GAP
                end
            end

            if plan.type == "custom" then
                makeAction(
                    "Interface\\RaidFrame\\ReadyCheck-Ready",
                    "Interface\\RaidFrame\\ReadyCheck-Ready",
                    function() if self.CompleteCustomPlan then self:CompleteCustomPlan(plan.id) end end,
                    "PLAN_ACTION_COMPLETE", "Complete the Plan"
                )
            end

            if hasTry then
                local tryRow = ns.UI.Factory:CreateTryCountClickable(row.headerFrame, {
                    height = ACTION_SIZE, frameLevelOffset = 15, showTooltip = true, popupOnRightClick = false,
                })
                tryRow:SetSize(tryW, ACTION_SIZE)
                tryRow:ClearAllPoints()
                tryRow:SetPoint("RIGHT", row.headerFrame, "RIGHT", -rightOffset, 0)
                tryRow:WnUpdateTryCount(plan.type, collectibleID, resolvedName)
                rightOffset = rightOffset + tryW + ACTION_GAP
            end

            row:Show()
        end
    end

    -- Sync row offsets after all cards are added (prevents gaps from mixed-height cards)
    CardLayoutManager:RecalculateAllPositions(layoutManager)
    PlanCardFactory:ReflowAllPlanCards(layoutManager)

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
-- REMOVED: OnPlansUpdated — UI.lua's SchedulePopulateContent handles WN_PLANS_UPDATED centrally.


-- ============================================================================
-- BROWSER (Mounts, Pets, Toys, Recipes)
-- ============================================================================

function WarbandNexus:DrawBrowser(parent, yOffset, width, category)
    parent._plansCardLayoutManager = nil

    -- Use SharedWidgets search bar (like Items tab)
    -- Create results container that can be refreshed independently
    local resultsContainer = CreateResultsContainer(parent, yOffset + 40, 10)
    if resultsContainer then
        resultsContainer._plansBrowseTopInset = yOffset + 40
    end
    if resultsContainer and SearchResultsRenderer and SearchResultsRenderer.PrepareContainer then
        SearchResultsRenderer:PrepareContainer(resultsContainer)
    end
    
    -- Create unique search ID for this category (e.g., "plans_mount", "plans_pet")
    local searchId = "plans_" .. (category or "unknown"):lower()
    local initialSearchText = SearchStateManager:GetQuery(searchId)
    
    local searchPlaceholder = format((ns.L and ns.L["SEARCH_CATEGORY_FORMAT"]) or "Search %s...", category)
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
-- ACHIEVEMENTS BROWSE (To-Do ▸ Achievements) — Collections-parity virtual list + accordion (AchievementBrowseVirtualList).
-- ============================================================================

local COLLECTED_COLOR_PLANS_ACH = "|cff33e533"
local DEFAULT_ICON_PLANS_ACHIEVEMENT = "Interface\\Icons\\Achievement_General"

function WarbandNexus:DrawAchievementsTable(parent, results, yOffset, width, searchText)
    searchText = searchText or ""

    if #results == 0 then
        if parent.plansAchBrowseRoot then
            parent.plansAchBrowseRoot:Hide()
        end
        if parent._plansAchBrowseState then
            parent._plansAchBrowseState._achOuterScrollActive = false
        end
        local searchId = "plans_achievement"
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, searchText, searchId)
        SearchStateManager:UpdateResults(searchId, 0)
        return height
    end

    if parent.plansAchBrowseRoot then
        parent.plansAchBrowseRoot:Show()
    end

    if not cachedCategoryTree then
        local allCategoryIDs = GetCategoryList() or {}
        local catData = {}
        local roots = {}
        for index = 1, #allCategoryIDs do
            local categoryID = allCategoryIDs[index]
            local categoryName, parentCategoryID = GetCategoryInfo(categoryID)
            catData[categoryID] = {
                id = categoryID,
                name = categoryName or ((ns.L and ns.L["UNKNOWN_CATEGORY"]) or "Unknown Category"),
                parentID = parentCategoryID,
                children = {},
                order = index,
            }
        end
        for ai = 1, #allCategoryIDs do
            local categoryID = allCategoryIDs[ai]
            local data = catData[categoryID]
            if data then
                if data.parentID and data.parentID > 0 then
                    if catData[data.parentID] then
                        table.insert(catData[data.parentID].children, categoryID)
                    end
                else
                    table.insert(roots, categoryID)
                end
            end
        end
        cachedCategoryTree = { categoryData = catData, rootCategories = roots }
    end

    local categoryData = {}
    for catID, src in pairs(cachedCategoryTree.categoryData) do
        categoryData[catID] = {
            id = src.id, name = src.name, parentID = src.parentID,
            children = src.children, order = src.order,
            achievements = {},
        }
    end
    local rootCategories = cachedCategoryTree.rootCategories

    local profileAchBrowse = WarbandNexus.db and WarbandNexus.db.profile
    local showCompletedAchBrowse = ProfileBool(profileAchBrowse, "plansShowCompleted", false)
    local showPlannedAchBrowse = ProfileBool(profileAchBrowse, "plansShowPlanned", false)
    -- Full uncollected browse only: mix of planned / not — suffix helps. Any filter that restricts to "on To-Do" makes (Planned) redundant noise.
    local showAchievementPlannedSuffix = (not showCompletedAchBrowse) and (not showPlannedAchBrowse)

    for ri = 1, #results do
        local achievement = results[ri]
        local categoryID = achievement.categoryID
        if not categoryID and GetAchievementCategory then
            categoryID = GetAchievementCategory(achievement.id)
            achievement.categoryID = categoryID
        end
        if categoryID and not categoryData[categoryID] and GetCategoryInfo then
            local walked = categoryID
            for _ = 1, 12 do
                local _, parentID = GetCategoryInfo(walked)
                if not parentID or parentID <= 0 then break end
                if categoryData[parentID] then
                    categoryID = parentID
                    achievement.categoryID = categoryID
                    break
                end
                walked = parentID
            end
        end
        if categoryData[categoryID] then
            achievement.isPlanned = self:IsAchievementPlanned(achievement.id)
            table.insert(categoryData[categoryID].achievements, achievement)
        end
    end

    local expandedGroups = ns.UI_GetExpandedGroups()
    local achExpandAll = self.achievementsExpandAllActive
    local searchActive = searchText ~= ""

    local collapsedHeaders = {}
    setmetatable(collapsedHeaders, {
        __index = function(t, k)
            local r = rawget(t, k)
            if r ~= nil then return r end
            if achExpandAll or searchActive then return false end
            if expandedGroups[k] then return false end
            return true
        end,
        __newindex = function(t, k, v)
            rawset(t, k, v)
            expandedGroups[k] = (v == false)
        end,
    })

    local layout = GetLayout()
    local achRowScale = ns.UI_ACHIEVEMENT_BROWSE_ROW_HEIGHT_SCALE or 1.1
    local baseRowH = layout.rowHeight or layout.ROW_HEIGHT or 26
    local ROW_H = math.max(18, math.floor(baseRowH * achRowScale + 0.5))
    local innerPad = 8
    local listInnerW = math.max(40, width - innerPad * 2)

    local rootFrame = parent.plansAchBrowseRoot
    if not rootFrame then
        rootFrame = CreateFrame("Frame", nil, parent)
        parent.plansAchBrowseRoot = rootFrame
    end
    if not parent._plansAchBrowseState then
        parent._plansAchBrowseState = {}
    end
    local st = parent._plansAchBrowseState

    local oldInnerScroll = st.achievementListScrollFrame
    if oldInnerScroll and oldInnerScroll.GetObjectType and oldInnerScroll:GetObjectType() == "ScrollFrame" then
        oldInnerScroll:Hide()
        if oldInnerScroll.SetScrollChild then
            oldInnerScroll:SetScrollChild(nil)
        end
        oldInnerScroll:SetParent(nil)
        st.achievementListScrollFrame = nil
        if st.achievementListScrollChild and st.achievementListScrollChild:GetParent() == oldInnerScroll then
            st.achievementListScrollChild = nil
        end
    end

    if not st.achievementListScrollChild or st.achievementListScrollChild:GetParent() ~= rootFrame then
        if st.achievementListScrollChild then
            st.achievementListScrollChild:SetParent(nil)
        end
        local scNew = ns.UI.Factory:CreateContainer(rootFrame, listInnerW, 1, false)
        scNew:SetWidth(listInnerW)
        st.achievementListScrollChild = scNew
    end

    local tabScrollChild = parent:GetParent()
    local mfAch = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local mainScrollAch = mfAch and mfAch.scroll
    if (not mainScrollAch) and tabScrollChild and tabScrollChild.GetParent then
        local p = tabScrollChild:GetParent()
        if p and p.GetObjectType and p:GetObjectType() == "ScrollFrame" then
            mainScrollAch = p
        end
    end

    rootFrame:ClearAllPoints()
    rootFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(yOffset or 0))
    rootFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(yOffset or 0))

    local scrollChild = st.achievementListScrollChild
    scrollChild:SetWidth(listInnerW)

    if mainScrollAch then
        if st._plansAchInnerScroll then
            st._plansAchInnerScroll:Hide()
            if st._plansAchInnerScroll.SetScrollChild then
                st._plansAchInnerScroll:SetScrollChild(nil)
            end
        end
        scrollChild:SetParent(rootFrame)
        scrollChild:ClearAllPoints()
        scrollChild:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 0, 0)
        st.achievementListScrollFrame = mainScrollAch
        st._achUseOuterScroll = true
        st._achOuterScrollFrame = mainScrollAch
        st._achOuterScrollChild = tabScrollChild
    else
        st._achUseOuterScroll = false
        st._achOuterScrollFrame = nil
        st._achOuterScrollChild = nil
        local sf = st._plansAchInnerScroll
        if not sf then
            sf = ns.UI.Factory:CreateScrollFrame(rootFrame, "UIPanelScrollFrameTemplate", true)
            st._plansAchInnerScroll = sf
        end
        sf:SetParent(rootFrame)
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 0, 0)
        sf:SetPoint("BOTTOMRIGHT", rootFrame, "BOTTOMRIGHT", 0, 0)
        sf:Show()
        scrollChild:SetParent(sf)
        sf:SetScrollChild(scrollChild)
        scrollChild:ClearAllPoints()
        scrollChild:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
        st.achievementListScrollFrame = sf
    end

    local scrollFrame = st.achievementListScrollFrame

    local _, totalPrev = ns.UI_AchievementBrowse_BuildFlatList(categoryData, rootCategories, collapsedHeaders, { rowHeightScale = achRowScale })
    rootFrame:SetHeight(math.max(1, totalPrev))
    if parent.SetHeight then
        parent:SetHeight(math.max(1, (yOffset or 0) + totalPrev + innerPad))
    end

    local rowPool = parent._plansAchBrowseRowPool
    if not rowPool then
        rowPool = {}
        parent._plansAchBrowseRowPool = rowPool
    end

    local function releaseRowFrame(f)
        if not f then return end
        f:Hide()
        f:ClearAllPoints()
        rowPool[#rowPool + 1] = f
    end

    local function refreshVisible()
        if st._achListRefreshVisible then
            st._achListRefreshVisible()
        end
    end

    local Factory = ns.UI.Factory

    local function acquireRow(scChild, listW, item, selectedID, onSelect, redraw, cf)
        local ach = item.achievement
        if not ach then return nil end
        local rowParent = scChild
        if item._collSectionKey and st._achSectionBodies and st._achSectionBodies[item._collSectionKey] then
            rowParent = st._achSectionBodies[item._collSectionKey]
        end
        local indent = item.indent or 0
        local rowItem = item
        if item._collRelY then
            rowItem = {
                achievement = ach,
                rowIndex = item.rowIndex,
                yOffset = item._collRelY,
                height = item.height,
                indent = indent,
            }
        end

        local row = table.remove(rowPool)
        if not row then
            row = Factory:CreateCollectionListRow(rowParent, ROW_H)
        else
            row:SetParent(rowParent)
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rowParent, "TOPLEFT", indent, -(rowItem.yOffset or 0))
        row:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", 0, -(rowItem.yOffset or 0))
        row:SetHeight(ROW_H)

        local title = FormatTextNumbers(ach.name or "")
        if ach.isPlanned and showAchievementPlannedSuffix then
            title = title .. " |cffffcc00(" .. ((ns.L and ns.L["PLANNED"]) or "Planned") .. ")|r"
        end
        local pointsStr = (ach.points and ach.points > 0) and (" (" .. ach.points .. " pts)") or ""
        local nameColor = ach.isCollected and COLLECTED_COLOR_PLANS_ACH or "|cffffffff"
        local labelText = nameColor .. title .. "|r" .. pointsStr

        local function IsTracked(id)
            return WarbandNexus.IsAchievementTracked and WarbandNexus:IsAchievementTracked(id)
        end

        local applyAchRowPlanSlots
        applyAchRowPlanSlots = function()
            local L = ns.L
            local col = ach.isCollected == true
            local tracked = IsTracked(ach.id)
            local plannedNow = WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(ach.id) or false
            local todoTip = plannedNow and ((L and L["TODO_SLOT_TOOLTIP_REMOVE"]) or "Click to remove from your To-Do list.")
                or (not col and ((L and L["TODO_SLOT_TOOLTIP_ADD"]) or "Click to add to your To-Do list.") or "")
            local trackTip = col and ((L and L["TRACK_SLOT_DISABLED_COMPLETED"]) or "Completed achievements cannot be tracked in objectives.")
                or (tracked and ((L and L["TRACK_SLOT_TOOLTIP_UNTRACK"]) or "Click to stop tracking in Blizzard objectives."))
                or ((L and L["TRACK_BLIZZARD_OBJECTIVES"]) or "Track in Blizzard objectives (max 10)")
            Factory:ApplyCollectionListRowContent(row, item.rowIndex or 1, ach.icon or DEFAULT_ICON_PLANS_ACHIEVEMENT, labelText, col, false, nil, nil, nil, {
                onTodo = plannedNow,
                onTrack = tracked,
                achievementRow = true,
                achievementCollected = col,
                todoTooltip = todoTip,
                trackTooltip = trackTip,
                onTodoClick = (plannedNow or not col) and function()
                    if not WarbandNexus then return end
                    if WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(ach.id) then
                        local plans = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.plans
                        if plans then
                            for pi = 1, #plans do
                                local p = plans[pi]
                                if p and p.id and p.type == PLAN_TYPES.ACHIEVEMENT and p.achievementID == ach.id then
                                    WarbandNexus:RemovePlan(p.id)
                                    break
                                end
                            end
                        end
                        ach.isPlanned = false
                        refreshVisible()
                    elseif not col and WarbandNexus.AddPlan then
                        WarbandNexus:AddPlan({
                            type = PLAN_TYPES.ACHIEVEMENT,
                            achievementID = ach.id,
                            name = ach.name,
                            icon = ach.icon,
                            points = ach.points,
                            source = ach.source,
                        })
                        ach.isPlanned = true
                        refreshVisible()
                    end
                end or nil,
                onTrackClick = (not col) and function()
                    if WarbandNexus.ToggleAchievementTracking then
                        WarbandNexus:ToggleAchievementTracking(ach.id)
                    end
                    applyAchRowPlanSlots()
                end or nil,
            })
            if row.label then
                local labelPad = layout.SIDE_MARGIN or (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 10
                row.label:SetPoint("RIGHT", row, "RIGHT", -labelPad, 0)
                if row.label.SetMouseClickEnabled then
                    row.label:SetMouseClickEnabled(false)
                end
            end
        end
        applyAchRowPlanSlots()

        if row._wnPlansTrackBtn then
            row._wnPlansTrackBtn:Hide()
            row._wnPlansTrackBtn:SetScript("OnEnter", nil)
            row._wnPlansTrackBtn:SetScript("OnLeave", nil)
            row._wnPlansTrackBtn:SetScript("OnClick", nil)
        end
        if row._wnPlansAddBtn then
            row._wnPlansAddBtn:Hide()
        end
        if row._wnPlansAddedFs then
            row._wnPlansAddedFs:Hide()
        end

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 6, 0)
            if GameTooltip.SetAchievementByID then
                GameTooltip:SetAchievementByID(ach.id)
            elseif ach.name then
                GameTooltip:SetText(ach.name, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:Show()
        return row
    end

    ns.UI_AchievementBrowse_Populate({
        state = st,
        scrollChild = scrollChild,
        listWidth = listInnerW,
        categoryData = categoryData,
        rootCategories = rootCategories,
        collapsedHeaders = collapsedHeaders,
        selectedAchievementID = nil,
        onSelectAchievement = nil,
        contentFrameForRefresh = parent,
        redrawFn = nil,
        acquireRow = acquireRow,
        releaseRowFrame = releaseRowFrame,
        scheduleVisibleSync = nil,
        rowHeightScale = achRowScale,
    })

    if Factory.UpdateScrollBarVisibility and scrollFrame and not st._achUseOuterScroll then
        Factory:UpdateScrollBarVisibility(scrollFrame)
    end

    SearchStateManager:UpdateResults("plans_achievement", #results)
    local totalH = st._achFlatListTotalHeight or 1
    rootFrame:SetHeight(math.max(1, totalH))
    return (yOffset or 0) + totalH + innerPad
end


-- ============================================================================
-- BROWSER RESULTS RENDERING (Separated for search refresh)
-- ============================================================================

-- Phase 4.4: Performance limit for browse results rendering
local MAX_BROWSE_RESULTS = 100
-- Collected fetch for Plans browse: Show Completed filters collected rows by isPlanned. A low cap (e.g. 50)
-- leaves tabs empty when the user's planned-completed entries are not among the first N collected (Achievements already used 99999).
local COLLECTED_BROWSE_FETCH_LIMIT = 99999

local function DrawPlansBrowseEmptyCard(parent, yOffset, width, category, searchText, showPlanned, showCompleted)
    local L = ns.L
    local labelCat = category or "item"
    local st = searchText or ""
    local hasSearch = st ~= ""
    local titleR, titleG, titleB = 1, 1, 1
    local titleStr
    local descStr
    if hasSearch then
        titleStr = (L and L["NO_RESULTS"]) or "No results"
        descStr = (L and L["TRY_ADJUSTING_SEARCH"]) or "Try adjusting your search or filters."
    elseif showCompleted and showPlanned then
        titleR, titleG, titleB = 1, 0.8, 0
        titleStr = (L and L["PLANS_BROWSE_EMPTY_PLANNED_ALL_TITLE"]) or "Nothing to show"
        descStr = (L and L["PLANS_BROWSE_EMPTY_PLANNED_ALL_DESC"])
            or "No planned items in this category match these filters. Add entries to your To-Do or adjust Show Planned / Show Completed."
    elseif showCompleted and not showPlanned then
        titleR, titleG, titleB = 0.3, 1, 0.3
        titleStr = (L and L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_TITLE"]) or "No completed To-Do items"
        descStr = (L and L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_DESC"])
            or "Nothing on your To-Do List in this category is collected or completed yet. Turn off Show Completed to see entries still in progress."
    elseif showPlanned and not showCompleted then
        titleR, titleG, titleB = 1, 0.8, 0
        titleStr = (L and L["PLANS_BROWSE_EMPTY_IN_PROGRESS_TITLE"]) or "No in-progress To-Do items"
        descStr = (L and L["PLANS_BROWSE_EMPTY_IN_PROGRESS_DESC"])
            or "Nothing on your To-Do List in this category is still uncollected. Turn on Show Completed to see finished ones, or add goals from this tab."
    else
        titleR, titleG, titleB = 0.3, 1, 0.3
        titleStr = (L and L["ALL_COLLECTED_CATEGORY"] and format(L["ALL_COLLECTED_CATEGORY"], labelCat))
            or ("All " .. labelCat .. "s collected!")
        descStr = (L and L["COLLECTED_EVERYTHING"]) or "You've collected everything in this category!"
    end
    local noResultsCard = CreateCard(parent, 80)
    noResultsCard:SetPoint("TOPLEFT", 0, -yOffset)
    noResultsCard:SetPoint("TOPRIGHT", -10, -yOffset)
    local noResultsText = FontManager:CreateFontString(noResultsCard, "title", "OVERLAY")
    noResultsText:SetPoint("CENTER", 0, 10)
    noResultsText:SetTextColor(titleR, titleG, titleB)
    noResultsText:SetText(titleStr)
    local noResultsDesc = FontManager:CreateFontString(noResultsCard, "body", "OVERLAY")
    noResultsDesc:SetPoint("TOP", noResultsText, "BOTTOM", 0, -8)
    noResultsDesc:SetTextColor(1, 1, 1)
    noResultsDesc:SetText(descStr)
    noResultsDesc:SetWidth(width - 40)
    noResultsDesc:SetJustifyH("CENTER")
    noResultsCard:Show()
    return yOffset + 100
end

function WarbandNexus:DrawBrowserResults(parent, yOffset, width, category, searchText)
    ns._plansAchOuterVirtualState = nil

    local scrollChildLayout = parent and parent:GetParent()

    -- Same path as search refresh: repool/recycle children so achievement accordion rebuild is clean.
    if SearchResultsRenderer and SearchResultsRenderer.PrepareContainer and parent then
        SearchResultsRenderer:PrepareContainer(parent)
    elseif parent and parent.GetChildren then
        local children = { parent:GetChildren() }
        for chi = 1, #children do
            local child = children[chi]
            if child and child.Hide then
                child:Hide()
            end
        end
    end

    if scrollChildLayout and category ~= "achievement" and parent._plansAchBrowseState then
        parent._plansAchBrowseState._achOuterScrollActive = false
    end

    if parent and parent.plansAchBrowseRoot and category ~= "achievement" then
        parent.plansAchBrowseRoot:Hide()
    end

    local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local showCompletedBrowse = ProfileBool(profile, "plansShowCompleted", false)
    local showPlannedBrowse = ProfileBool(profile, "plansShowPlanned", false)
    
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

            if category == "achievement" and parent._plansAchBrowseState then
                parent._plansAchBrowseState._achOuterScrollActive = false
            end

            local newYOffset = UI_CreateLoadingStateCard(
                parent, 
                yOffset, 
                loadingStateData, 
                format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName)
            )
            return newYOffset
        else
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint("|cffff0000[WN PlansUI]|r UI_CreateLoadingStateCard not found!")
            end
            return yOffset + 120
        end
    end
    
    -- Fetch lists: neither checkbox = uncollected only; Show Completed = use collected list (filtered to planned);
    -- Show Planned without Completed = uncollected + planned; both = union of planned from both lists.
    local needUncollected = (not showCompletedBrowse) or (showPlannedBrowse and showCompletedBrowse)
    local needCollected = showCompletedBrowse

    local resultsUncollected = {}
    local resultsCollected = {}

    local dbgPlansBrowse = IsDebugModeEnabled and IsDebugModeEnabled()
    if category == "mount" then
        if needUncollected then resultsUncollected = self:GetUncollectedMounts(searchText, 50) end
        if needCollected then resultsCollected = self.GetCollectedMounts and self:GetCollectedMounts(searchText, COLLECTED_BROWSE_FETCH_LIMIT) or {} end
        if dbgPlansBrowse then
        end
    elseif category == "pet" then
        if needUncollected then resultsUncollected = self:GetUncollectedPets(searchText, 50) end
        if needCollected then resultsCollected = self.GetCollectedPets and self:GetCollectedPets(searchText, COLLECTED_BROWSE_FETCH_LIMIT) or {} end
        if dbgPlansBrowse then
        end
    elseif category == "toy" then
        if needUncollected then resultsUncollected = self:GetUncollectedToys(searchText, 50) end
        if needCollected then resultsCollected = self.GetCollectedToys and self:GetCollectedToys(searchText, COLLECTED_BROWSE_FETCH_LIMIT) or {} end
        if dbgPlansBrowse then
        end
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

            if category == "achievement" and parent._plansAchBrowseState then
                parent._plansAchBrowseState._achOuterScrollActive = false
            end

            local newYOffset = UI_CreateLoadingStateCard(
                parent, yOffset, loadingStateData,
                format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName)
            )
            return newYOffset
        end
    end

    if category == "transmog" then
        -- Transmog browser with sub-categories
        return self:DrawTransmogBrowser(parent, yOffset, width)
    elseif category == "illusion" then
        if needUncollected then resultsUncollected = self:GetUncollectedIllusions(searchText, 50) end
        if needCollected then resultsCollected = self.GetCollectedIllusions and self:GetCollectedIllusions(searchText, COLLECTED_BROWSE_FETCH_LIMIT) or {} end
    elseif category == "title" then
        if needUncollected then resultsUncollected = self:GetUncollectedTitles(searchText, 50) end
        if needCollected then resultsCollected = self.GetCollectedTitles and self:GetCollectedTitles(searchText, COLLECTED_BROWSE_FETCH_LIMIT) or {} end
    elseif category == "achievement" then
        if needUncollected then resultsUncollected = self:GetUncollectedAchievements(searchText, 99999) end
        if needCollected then resultsCollected = self.GetCompletedAchievements and self:GetCompletedAchievements(searchText, 99999) or {} end

        -- Re-check loading: GetUncollected/CompletedAchievements may have triggered scan (store empty)
        if categoryState.isLoading then
            if parent._plansAchBrowseState then
                parent._plansAchBrowseState._achOuterScrollActive = false
            end
            if parent.plansAchBrowseRoot then
                parent.plansAchBrowseRoot:Hide()
            end
            local loadingStateData = {
                isLoading = true,
                loadingProgress = categoryState.loadingProgress or 0,
                currentStage = categoryState.currentStage or ((ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."),
            }
            local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
            if UI_CreateLoadingStateCard then
                local displayName = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements"
                return UI_CreateLoadingStateCard(parent, yOffset, loadingStateData,
                    format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName))
            end
        end

        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsAchievementPlanned(item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsAchievementPlanned(item.id)
        end
        local achResults = MergePlansBrowseResults(resultsCollected, resultsUncollected, showPlannedBrowse, showCompletedBrowse)
        local achievementHeight = self:DrawAchievementsTable(parent, achResults, yOffset, width, searchText)
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
                format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName))
        end
    end
    
    -- isPlanned + merge matrix (mount, pet, toy, illusion, title)
    if category == "mount" then
        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsMountPlanned(item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsMountPlanned(item.id)
        end
    elseif category == "pet" then
        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsPetPlanned(item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsPetPlanned(item.id)
        end
    elseif category == "toy" then
        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsItemPlanned(PLAN_TYPES.TOY, item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsItemPlanned(PLAN_TYPES.TOY, item.id)
        end
    elseif category == "illusion" then
        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsIllusionPlanned(item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsIllusionPlanned(item.id)
        end
    elseif category == "title" then
        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsTitlePlanned(item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsTitlePlanned(item.id)
        end
    end

    local results = MergePlansBrowseResults(resultsCollected, resultsUncollected, showPlannedBrowse, showCompletedBrowse)

    if #results == 0 then
        if dbgPlansBrowse then
        end
        return DrawPlansBrowseEmptyCard(parent, yOffset, width, category, searchText, showPlannedBrowse, showCompletedBrowse)
    end

    table.sort(results, function(a, b)
        return SafeLower(a.name) < SafeLower(b.name)
    end)

    -- Phase 4.4: Limit browse results rendering for performance
    local totalResults = #results
    local resultsToRender = math.min(totalResults, MAX_BROWSE_RESULTS)
    
    -- === 2-COLUMN CARD GRID (metrics match To-Do expandable rows — SharedWidgets ns.UI_PLANS_CARD_METRICS) ===
    local PCM = ns.UI_PLANS_CARD_METRICS
    local cardSpacing = (PCM and PCM.gridSpacing) or 8
    local cardWidth = ns.UI_PlansCardGridColumnWidth and ns.UI_PlansCardGridColumnWidth(width)
        or math.max(100, (width - cardSpacing) / 2)
    local cardHeight = (PCM and PCM.browseCardHeight) or 105
    local browseIconTop = (PCM and PCM.browseIconTopInset) or 10
    local browseIconLeft = (PCM and PCM.browseIconLeftInset) or 10
    local browseIconBox = (PCM and PCM.browseIconContainerSize) or 45
    local todoIconSz = (PCM and PCM.todoIconSize) or 41
    local todoBadgeSz = (PCM and PCM.todoTypeBadgeSize) or 24
    local col = 0
    
    -- Show truncation message if results were limited
    if totalResults > MAX_BROWSE_RESULTS then
        local truncationMsg = FontManager:CreateFontString(parent, "body", "OVERLAY")
        truncationMsg:SetPoint("TOPLEFT", 0, -yOffset)
        truncationMsg:SetPoint("TOPRIGHT", -10, -yOffset)
        truncationMsg:SetJustifyH("CENTER")
        local showingFormat = (ns.L and ns.L["SHOWING_X_OF_Y"]) or "Showing %d of %d results"
        truncationMsg:SetText("|cff888888" .. format(showingFormat, MAX_BROWSE_RESULTS, totalResults) .. "|r")
        yOffset = yOffset + 24
    end

    local planBrowseSrcIconSz = (ns.UI_PLAN_SOURCE_ICON_LG) or math.floor(16 * 1.3 + 0.5)
    local planBrowseTypeBadgeSz = todoBadgeSz
    
    for i = 1, resultsToRender do
        local item = results[i]
        item.category = category
        -- Resolve empty source from API so browser shows same source as collection tabs (e.g. Voidstorm Fishing).
        local sourceMissing = not item.source
        if not sourceMissing and item.source then
            if issecretvalue and issecretvalue(item.source) then
                sourceMissing = true
            elseif item.source == "" then
                sourceMissing = true
            end
        end
        if sourceMissing and item.id then
            if category == "mount" and C_MountJournal and C_MountJournal.GetMountInfoExtraByID then
                local ok, _, _, src = pcall(C_MountJournal.GetMountInfoExtraByID, item.id)
                if ok and src and type(src) == "string" and not (issecretvalue and issecretvalue(src)) and src ~= "" then
                    item.source = src
                end
            elseif category == "pet" and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
                local ok, _, _, _, _, src = pcall(C_PetJournal.GetPetInfoBySpeciesID, item.id)
                if ok and src and type(src) == "string" and not (issecretvalue and issecretvalue(src)) and src ~= "" then
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
        
        -- === ICON (same footprint as To-Do expandable row: todoIconSize inside browseIconContainerSize) ===
        local iconBorder = ns.UI.Factory:CreateContainer(card, browseIconBox, browseIconBox)
        iconBorder:SetPoint("TOPLEFT", browseIconLeft, -browseIconTop)
        iconBorder:EnableMouse(false)
        
        -- Create icon texture or atlas
        local iconTexture = item.iconAtlas or item.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        local iconIsAtlas = (item.iconAtlas ~= nil)
        
        local iconFrameObj = CreateIcon(card, iconTexture, todoIconSz, iconIsAtlas, nil, false)
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
            local shieldFrame = ns.UI.Factory:CreateContainer(card, planBrowseTypeBadgeSz, planBrowseTypeBadgeSz)
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
            pointsText:SetText(format("|cff%02x%02x%02x" .. ((ns.L and ns.L["POINTS_FORMAT"]) or "%d Points") .. "|r", 
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
                iconFrame = ns.UI.Factory:CreateContainer(card, planBrowseTypeBadgeSz, planBrowseTypeBadgeSz)
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
            typeBadge:SetText(format("|cff%02x%02x%02x%s|r", 
                typeColor[1]*255, typeColor[2]*255, typeColor[3]*255,
                typeName))
            typeBadge:EnableMouse(false)  -- Allow clicks to pass through
        end
        
        -- === LINE 3: Source Info (below icon row — aligned with To-Do chrome) ===
        local line3Y = -(browseIconTop + browseIconBox + 4)
        
        -- TITLE-SPECIFIC: Show source achievement with clickable link
        if category == "title" and item.sourceAchievement then
            local achievementText = FontManager:CreateFontString(card, "body", "OVERLAY")
            achievementText:SetPoint("TOPLEFT", 10, line3Y)
            achievementText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
            -- Use localized strings for Source label and Achievement type
            local sourceLabel = NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:")
            local achievementType = (ns.L and ns.L["SOURCE_TYPE_ACHIEVEMENT"]) or (BATTLE_PET_SOURCE_6 or "Achievement")
            local sourceText = (ns.L and ns.L["SOURCE_ACHIEVEMENT_FORMAT"] and format(ns.L["SOURCE_ACHIEVEMENT_FORMAT"], sourceLabel, achievementType, item.sourceAchievement)) or (sourceLabel .. " |cff00ff00[" .. achievementType .. " " .. item.sourceAchievement .. "]|r")
            achievementText:SetText(format("|TInterface\\Icons\\Achievement_General:%d:%d|t ", planBrowseSrcIconSz, planBrowseSrcIconSz) .. sourceText)
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
                    
                    if IsDebugModeEnabled and IsDebugModeEnabled() then
                        local aid = item.sourceAchievement
                        if aid ~= nil and not (issecretvalue and issecretvalue(aid)) then
                        end
                    end
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
            vendorText:SetText((ns.UI_PlanSourceIconMarkup and ns.UI_PlanSourceIconMarkup("class", planBrowseSrcIconSz) or format("|A:Class:%d:%d|a", planBrowseSrcIconSz, planBrowseSrcIconSz)) .. " " .. NormalizeColonLabelSpacing((ns.L and ns.L["VENDOR_LABEL"]) or "Vendor:") .. firstSource.vendor)
            vendorText:SetTextColor(1, 1, 1)
            vendorText:SetJustifyH("LEFT")
            vendorText:SetWordWrap(true)
            vendorText:SetMaxLines(2)
            vendorText:SetNonSpaceWrap(false)
        elseif firstSource.npc then
            local npcText = FontManager:CreateFontString(card, "body", "OVERLAY")
            npcText:SetPoint("TOPLEFT", 10, line3Y)
            npcText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            local _srcIcon = ns.UI_PlanSourceIconMarkup
            local _lootMark = _srcIcon and _srcIcon("loot", planBrowseSrcIconSz) or format("|A:Banker:%d:%d|a", planBrowseSrcIconSz, planBrowseSrcIconSz)
            npcText:SetText(_lootMark .. " " .. NormalizeColonLabelSpacing((ns.L and ns.L["DROP_LABEL"]) or "Drop:") .. firstSource.npc)
            npcText:SetTextColor(1, 1, 1)
            npcText:SetJustifyH("LEFT")
            npcText:SetWordWrap(true)
            npcText:SetMaxLines(2)
            npcText:SetNonSpaceWrap(false)
        elseif firstSource.faction then
            local factionText = FontManager:CreateFontString(card, "body", "OVERLAY")
            factionText:SetPoint("TOPLEFT", 10, line3Y)
            factionText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            local factionLabel = NormalizeColonLabelSpacing((ns.L and ns.L["FACTION_LABEL"]) or "Faction:")
            local displayText = (ns.UI_PlanSourceIconMarkup and ns.UI_PlanSourceIconMarkup("class", planBrowseSrcIconSz) or format("|A:Class:%d:%d|a", planBrowseSrcIconSz, planBrowseSrcIconSz)) .. " " .. factionLabel .. firstSource.faction
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
            local zoneY = (firstSource.vendor or firstSource.npc or firstSource.faction) and (line3Y - 22) or line3Y
            zoneText:SetPoint("TOPLEFT", 10, zoneY)
            zoneText:SetPoint("RIGHT", card, "RIGHT", -70, 0)  -- Leave space for + Add button
            local _srcIconZ = ns.UI_PlanSourceIconMarkup
            local _locMark = _srcIconZ and _srcIconZ("location", planBrowseSrcIconSz) or format("|A:poi-islands-table:%d:%d|a", planBrowseSrcIconSz, planBrowseSrcIconSz)
            zoneText:SetText(_locMark .. " " .. NormalizeColonLabelSpacing((ns.L and ns.L["ZONE_LABEL"]) or "Zone:") .. firstSource.zone)
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
                if rawText and issecretvalue and issecretvalue(rawText) then
                    rawText = ""
                end
                if rawText ~= "" and WarbandNexus.CleanSourceText then
                    rawText = WarbandNexus:CleanSourceText(rawText)
                    if type(rawText) ~= "string" or (issecretvalue and issecretvalue(rawText)) then
                        rawText = ""
                    end
                end
                
                -- Extract progress if it exists
                local description, progress = rawText:match("^(.-)%s*(Progress:%s*.+)$")
                if description and issecretvalue and issecretvalue(description) then
                    description = nil
                end
                
                local lastElement = nil
                
                -- === INFORMATION (Description) - BELOW icon, WHITE color ===
                if description and not (issecretvalue and issecretvalue(description)) and description ~= "" then
                    local infoText = FontManager:CreateFontString(card, "body", "OVERLAY")
                    infoText:SetPoint("TOPLEFT", 10, line3Y)
                    infoText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    infoText:SetText("|cff88ff88" .. NormalizeColonLabelSpacing((ns.L and ns.L["INFORMATION_LABEL"]) or "Information:") .. "|r |cffffffff" .. description .. "|r")
                    infoText:SetJustifyH("LEFT")
                    infoText:SetWordWrap(true)
                    infoText:SetMaxLines(2)
                    infoText:SetNonSpaceWrap(false)
                    lastElement = infoText
                elseif item.description and not (issecretvalue and issecretvalue(item.description)) and item.description ~= "" then
                    local infoText = FontManager:CreateFontString(card, "body", "OVERLAY")
                    infoText:SetPoint("TOPLEFT", 10, line3Y)
                    infoText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    infoText:SetText("|cff88ff88" .. NormalizeColonLabelSpacing((ns.L and ns.L["INFORMATION_LABEL"]) or "Information:") .. "|r |cffffffff" .. FormatTextNumbers(item.description) .. "|r")
                    infoText:SetJustifyH("LEFT")
                    infoText:SetWordWrap(true)
                    infoText:SetMaxLines(2)
                    infoText:SetNonSpaceWrap(false)
                    lastElement = infoText
                end
                
                -- === PROGRESS - BELOW information, NO spacing ===
                if progress and not (issecretvalue and issecretvalue(progress)) then
                    local progressText = FontManager:CreateFontString(card, "body", "OVERLAY")
                    if lastElement then
                        progressText:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, -2)
                    else
                        progressText:SetPoint("TOPLEFT", 10, line3Y)
                    end
                    progressText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    local progressLabelRaw = (ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:"
                    local cleanProgress = progress:gsub(progressLabelRaw:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "%s*", "")
                    progressText:SetText("|cffffcc00" .. NormalizeColonLabelSpacing(progressLabelRaw) .. "|r |cffffffff" .. cleanProgress .. "|r")
                    progressText:SetJustifyH("LEFT")
                    progressText:SetWordWrap(false)
                    lastElement = progressText
                end
                
                -- === REWARD - BELOW progress WITH spacing (one line gap) ===
                local displayRewardText = item.rewardText
                if displayRewardText and issecretvalue and issecretvalue(displayRewardText) then
                    displayRewardText = nil
                end
                if (not displayRewardText or displayRewardText == "") and item.id and WarbandNexus.GetAchievementRewardInfo then
                    local ri = WarbandNexus:GetAchievementRewardInfo(item.id)
                    if ri then
                        local rt = ri.title or ri.itemName
                        if rt and not (issecretvalue and issecretvalue(rt)) then
                            displayRewardText = rt
                        end
                    end
                end
                if displayRewardText and not (issecretvalue and issecretvalue(displayRewardText)) and displayRewardText ~= "" then
                    local rewardText = FontManager:CreateFontString(card, "body", "OVERLAY")
                    if lastElement then
                        rewardText:SetPoint("TOPLEFT", lastElement, "BOTTOMLEFT", 0, -14)
                    else
                        rewardText:SetPoint("TOPLEFT", 10, line3Y)
                    end
                    rewardText:SetPoint("RIGHT", card, "RIGHT", -70, 0)
                    rewardText:SetText("|cff88ff88" .. NormalizeColonLabelSpacing((ns.L and ns.L["REWARD_LABEL"]) or "Reward:") .. "|r |cffffffff" .. displayRewardText .. "|r")
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
                        sourceText:SetText((ns.UI_PlanSourceIconMarkup and ns.UI_PlanSourceIconMarkup("class", planBrowseSrcIconSz) or format("|A:Class:%d:%d|a", planBrowseSrcIconSz, planBrowseSrcIconSz)) .. " |cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:") .. "|r |cffffffff" .. (item.source or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")) .. "|r")
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

        -- Right-click: set try count (same rules as My Plans), including Mounts/Pets/Toys/Illusions browser cards
        if browserTryTypes[category] and item.id then
            local tryId = item.id
            local tryName = item.name
            local tryCat = category
            local prevMouseDown = nil
            do
                local ok, res = pcall(function() return card:GetScript("OnMouseDown") end)
                if ok then prevMouseDown = res end
            end
            card:SetScript("OnMouseDown", function(self, button)
                if button == "RightButton" then
                    if WarbandNexus and WarbandNexus.ShouldShowTryCountInUI
                        and WarbandNexus:ShouldShowTryCountInUI(tryCat, tryId)
                        and ns.UI_ShowTryCountPopup then
                        ns.UI_ShowTryCountPopup(tryCat, tryId, tryName)
                    end
                    return
                end
                if prevMouseDown then
                    prevMouseDown(self, button)
                end
            end)
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
    local currentName = SafePlayerName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local currentRealm = SafeRealmName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local _, currentClass = UnitClass("player")
    local classColors = RAID_CLASS_COLORS[currentClass]
    
    -- Create external window using helper
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "CustomPlanDialog",
        title = (ns.L and ns.L["CREATE_CUSTOM_PLAN"]) or "Create Custom Plan",
        icon = "Bonus-Objective-Star",  -- Use atlas for custom plans
        iconIsAtlas = true,
        width = 450,
        height = 500,  -- Title + description + reset cycle + duration + infinite option
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
    titleLabel:SetText("|cff" .. format("%02x%02x%02x", COLORS.accent[1]*255, COLORS.accent[2]*255, COLORS.accent[3]*255) .. ((ns.L and ns.L["TITLE_LABEL"]) or "Title:") .. "|r")
    
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
    titleInput:SetTextColor(1, 1, 1, 1)
    titleInput:SetAutoFocus(false)
    titleInput:SetMaxLetters(32)  -- Max 32 characters
    titleInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    titleInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- Prevent Enter key from creating new lines
    titleInput:SetScript("OnChar", function(self, char)
        if char == "\n" or char == "\r" then
            local text = self:GetText()
            if not text or (issecretvalue and issecretvalue(text)) then return end
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
    descLabel:SetText("|cff" .. format("%02x%02x%02x", COLORS.accent[1]*255, COLORS.accent[2]*255, COLORS.accent[3]*255) .. NormalizeColonLabelSpacing((ns.L and ns.L["DESCRIPTION_LABEL"]) or "Description:") .. "|r")
    
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
    descInput:SetTextColor(1, 1, 1, 1)
    descInput:SetAutoFocus(false)
    descInput:SetMultiLine(false)  -- Single line only - prevents Enter from creating new lines
    descInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    descInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    -- Limit to 300 characters total, max 30 characters per word
    descInput:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if not text then return end
        if issecretvalue and issecretvalue(text) then return end
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
        if modified then
            local cur = self:GetText()
            if cur and issecretvalue and issecretvalue(cur) then return end
            if text ~= cur then
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
            if not text or (issecretvalue and issecretvalue(text)) then return end
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
    resetLabel:SetText("|cff" .. format("%02x%02x%02x", COLORS.accent[1]*255, COLORS.accent[2]*255, COLORS.accent[3]*255) .. ((ns.L and ns.L["RESET_CYCLE_LABEL"]) or "Reset Cycle:") .. "|r")
    
    -- Reset cycle toggle state
    local selectedResetType = "none"
    local selectedCycleCount = 7  -- Default cycle count
    local selectedInfiniteRepeat = false
    
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
    durationRow:SetSize(420, 54)
    durationRow:SetPoint("TOPLEFT", 12, -275)
    durationRow:Hide()
    
    local durationLabel = FontManager:CreateFontString(durationRow, "body", "OVERLAY")
    durationLabel:SetPoint("TOPLEFT", 0, -2)
    durationLabel:SetTextColor(0.7, 0.7, 0.7)
    
    -- Minus button
    local minusBtn = CreateFrame("Button", nil, durationRow, "BackdropTemplate")
    minusBtn:SetSize(28, 28)
    minusBtn:SetPoint("TOPLEFT", 160, -2)
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
    countDisplay:SetPoint("TOPLEFT", minusBtn, "TOPRIGHT", 12, 0)
    countDisplay:SetTextColor(1, 1, 1)
    countDisplay:SetWidth(30)
    countDisplay:SetJustifyH("CENTER")
    
    -- Plus button
    local plusBtn = CreateFrame("Button", nil, durationRow, "BackdropTemplate")
    plusBtn:SetSize(28, 28)
    plusBtn:SetPoint("TOPLEFT", countDisplay, "TOPRIGHT", 12, 0)
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
    unitLabel:SetPoint("TOPLEFT", plusBtn, "TOPRIGHT", 10, 0)
    unitLabel:SetTextColor(0.7, 0.7, 0.7)

    local foreverCb = CreateThemedCheckbox(durationRow, false)
    if foreverCb then
        foreverCb:SetPoint("TOPLEFT", durationRow, "TOPLEFT", 0, -34)
    end
    local foreverLabel = FontManager:CreateFontString(durationRow, "body", "OVERLAY")
    if foreverCb then
        foreverLabel:SetPoint("LEFT", foreverCb, "RIGHT", 8, 0)
    else
        foreverLabel:SetPoint("TOPLEFT", durationRow, "TOPLEFT", 0, -34)
    end
    foreverLabel:SetPoint("TOPRIGHT", durationRow, "TOPRIGHT", 0, -34)
    foreverLabel:SetJustifyH("LEFT")
    foreverLabel:SetTextColor(0.75, 0.75, 0.75)
    foreverLabel:SetWordWrap(true)
    foreverLabel:SetMaxLines(2)
    foreverLabel:SetText((ns.L and ns.L["CUSTOM_PLAN_REPEAT_UNTIL_REMOVED"]) or "Repeat until this plan is deleted")
    
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

    local function UpdateInfiniteDurationUI()
        if foreverCb then
            foreverCb:SetChecked(selectedInfiniteRepeat)
            if foreverCb.innerDot then
                foreverCb.innerDot:SetShown(selectedInfiniteRepeat)
            end
        end
        if selectedInfiniteRepeat then
            minusBtn:Disable()
            plusBtn:Disable()
            countDisplay:SetWidth(56)
            countDisplay:SetText("--")
            unitLabel:SetText("")
        else
            minusBtn:Enable()
            plusBtn:Enable()
            countDisplay:SetWidth(30)
            UpdateDurationDisplay()
            UpdateUnitLabel()
        end
    end

    if foreverCb then
        foreverCb:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            if self.innerDot then
                self.innerDot:SetShown(checked)
            end
            selectedInfiniteRepeat = (checked == true or checked == 1)
            UpdateInfiniteDurationUI()
        end)
    end
    
    -- Update button visuals based on selection
    local function UpdateResetButtons()
        for bi = 1, #resetButtons do
            local btn = resetButtons[bi]
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
            selectedInfiniteRepeat = false
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
            UpdateInfiniteDurationUI()
            durationRow:Show()
        end
    end
    
    for bi = 1, #resetButtons do
        local btn = resetButtons[bi]
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
        if title and issecretvalue and issecretvalue(title) then return end
        if description and issecretvalue and issecretvalue(description) then
            description = nil
        end
        
        if title and title ~= "" then
            local cycleCount = (selectedResetType ~= "none") and selectedCycleCount or nil
            local infiniteRepeat = (selectedResetType ~= "none") and selectedInfiniteRepeat or false
            WarbandNexus:SaveCustomPlan(title, description, selectedResetType, cycleCount, infiniteRepeat)
            dialog.Close()
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

function WarbandNexus:SaveCustomPlan(title, description, resetType, cycleCount, infiniteRepeat)
    if not self.db.global.customPlans then
        self.db.global.customPlans = {}
    end

    local wantInfinite = infiniteRepeat and resetType and resetType ~= "none"
    local finiteCount = (not wantInfinite and cycleCount) or nil
    if not wantInfinite and (not finiteCount or finiteCount < 1) then
        finiteCount = 1
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
            infiniteRepeat = wantInfinite or false,
            totalCycles = wantInfinite and nil or finiteCount,
            remainingCycles = wantInfinite and nil or finiteCount,
        } or nil,
    }
    
    table.insert(self.db.global.customPlans, customPlan)

    -- Resolve display data immediately so My Plans renders complete info
    if self._ResolveSinglePlan then
        self:_ResolveSinglePlan(customPlan, time())
    end
    self:SendMessage(E.PLANS_UPDATED, {
        action = "custom_created",
        planID = customPlan.id,
    })
end

function WarbandNexus:GetCustomPlans()
    return self.db.global.customPlans or {}
end

function WarbandNexus:CompleteCustomPlan(planId)
    if not self.db.global.customPlans then return false end

    local customPlansList = self.db.global.customPlans
    for pi = 1, #customPlansList do
        local plan = customPlansList[pi]
        if plan.id == planId then
            if plan.completed then return true end -- Already completed
            
            plan.completed = true
            self:Print(format((ns.L and ns.L["CUSTOM_PLAN_COMPLETED"]) or "Custom plan '%s' |cff00ff00completed|r", FormatTextNumbers(plan.name)))

            -- Track completion time for recurring reset
            if plan.resetCycle and plan.resetCycle.enabled then
                plan.resetCycle.completedAt = time()
            end

            -- Fire event immediately so UI refreshes instantly
            self:SendMessage(E.PLANS_UPDATED, {
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
    
    for i = 1, #self.db.global.customPlans do
        local plan = self.db.global.customPlans[i]
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
    local currentName = SafePlayerName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local currentRealm = SafeRealmName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    
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
        local descText = (ns.L and ns.L["WEEKLY_PLAN_EXISTS_DESC"] and format(ns.L["WEEKLY_PLAN_EXISTS_DESC"], currentName .. "-" .. currentRealm)) or (currentName .. "-" .. currentRealm .. " already has an active weekly vault plan. You can find it in the 'My Plans' category.")
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
                    milestoneText:SetText(format("%s / %s", FormatNumber(math.min(current, thresholds[i])), FormatNumber(thresholds[i])))
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
        for si = 1, #slotOptions do
            local opt = slotOptions[si]
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
    
    local currentName = SafePlayerName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local currentRealm = SafeRealmName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
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
        local charFullName = currentName .. "-" .. currentRealm
        local dailyExistsDesc = (ns.L and ns.L["DAILY_PLAN_EXISTS_DESC"]) or "%s already has an active weekly quest plan. You can find it in the 'Weekly Progress' category."
        infoText:SetText("|cffaaaaaa" .. format(dailyExistsDesc, charFullName) .. "|r")
        
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
    contentLabel:SetText("|cff888888" .. ((ns.L and ns.L["CONTENT_MIDNIGHT"]) or "Midnight") .. "|r")
    
    -- Quest type checkboxes
    local selectedQuestTypes = {
        weeklyQuests = true,
        worldQuests  = true,
        dailyQuests  = true,
        events       = true,
    }
    
    local questTypeY = -68
    local sectionLabel = FontManager:CreateFontString(contentFrame, "subtitle", "OVERLAY", "accent")
    sectionLabel:SetPoint("TOPLEFT", 16, questTypeY)
    sectionLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    sectionLabel:SetText((ns.L and ns.L["QUEST_TYPES"]) or "Track Categories:")
    
    local CATEGORIES = ns.QUEST_CATEGORIES or {}
    local categoryDescs = {
        weeklyQuests = (ns.L and ns.L["QUEST_CATEGORY_DESC_WEEKLY"]) or "Weekly objectives, hunts, sparks, world boss, delves",
        worldQuests  = (ns.L and ns.L["QUEST_CATEGORY_DESC_WORLD"]) or "Zone-wide repeatable world quests",
        dailyQuests  = (ns.L and ns.L["QUEST_CATEGORY_DESC_DAILY"]) or "Daily repeatable quests from NPCs",
        events       = (ns.L and ns.L["QUEST_CATEGORY_DESC_EVENTS"]) or "Bonus objectives, tasks, and activities",
    }
    
    for i = 1, #CATEGORIES do
        local catInfo = CATEGORIES[i]
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

