--[[
    Warband Nexus - Plan Card Factory
    Centralized factory for creating plan cards with unified structure
    Supports all plan types: Achievement, Mount, Pet, Toy, Illusion, Title, Weekly Vault, Daily Quest
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local issecretvalue = issecretvalue

-- Import shared UI components
local CreateCard = ns.UI_CreateCard
local CreateIcon = ns.UI_CreateIcon
local ApplyVisuals = ns.UI_ApplyVisuals
local CardLayoutManager = ns.UI_CardLayoutManager
local FontManager = ns.FontManager  -- Centralized font management
local FormatTextNumbers = ns.UI_FormatTextNumbers
local FormatNumber = ns.UI_FormatNumber
local NormalizeColonLabelSpacing = ns.UI_NormalizeColonLabelSpacing

local PlanCardFactory = {}

-- Type colors
local TYPE_COLORS = {
    mount = {0.6, 0.8, 1},
    pet = {0.5, 1, 0.5},
    toy = {1, 0.9, 0.2},
    recipe = {0.8, 0.8, 0.5},
    achievement = {1, 0.8, 0.2},
    transmog = {0.8, 0.5, 1},
    custom = {1, 0.2, 0.2},  -- Will use COLORS.accent in actual usage
    weekly_vault = {1, 0.2, 0.2},  -- Will use COLORS.accent
    illusion = {0.8, 0.5, 1},
    title = {0.6, 0.6, 0.6},
}

-- Type names
local TYPE_NAMES = {
    mount = (ns.L and ns.L["TYPE_MOUNT"]) or "Mount",
    pet = (ns.L and ns.L["TYPE_PET"]) or "Pet",
    toy = (ns.L and ns.L["TYPE_TOY"]) or "Toy",
    recipe = (ns.L and ns.L["TYPE_RECIPE"]) or "Recipe",
    illusion = (ns.L and ns.L["TYPE_ILLUSION"]) or "Illusion",
    title = (ns.L and ns.L["TYPE_TITLE"]) or "Title",
    custom = (ns.L and ns.L["TYPE_CUSTOM"]) or "Custom",
    transmog = (ns.L and ns.L["TYPE_TRANSMOG"]) or "Transmog",
}

-- Type icon atlas mapping (used by both PlanCardFactory and PlansTrackerWindow as the canonical
-- "what type of plan is this?" visual cue rendered before the name).
local TYPE_ICONS = {
    mount = "dragon-rostrum",
    pet = "WildBattlePetCapturable",
    toy = "CreationCatalyst-32x32",
    illusion = "UpgradeItem-32x32",
    title = "poi-legendsoftheharanir",
    transmog = "poi-transmogrifier",
    achievement = "UI-Achievement-Shield-NoPoints",
}

-- Inline |A:...|a markers (Drop / Quest / Location / Vendor): modest size so stacked rows do not crowd.
local PLAN_SRC_ICON_LG = math.floor(16 * 1.12 + 0.5)
local PLAN_SRC_ICON_MD = math.floor(14 * 1.12 + 0.5)
local PLAN_SRC_ICON_SM = math.floor(12 * 1.12 + 0.5)
ns.UI_PLAN_SOURCE_ICON_LG = PLAN_SRC_ICON_LG
ns.UI_PLAN_SOURCE_ICON_MD = PLAN_SRC_ICON_MD
ns.UI_PLAN_SOURCE_ICON_SM = PLAN_SRC_ICON_SM

-- Vertical gap after each source row; GetStringHeight often under-counts lines with embedded atlas icons.
local PLAN_SRC_ROW_VPAD = 7

local function PlanSourceAdvanceY(y, fontString, useIconFloor)
    local lh = fontString:GetStringHeight() or 14
    local block = useIconFloor and math.max(lh, PLAN_SRC_ICON_LG + 4) or math.max(lh, 16)
    return y - block - PLAN_SRC_ROW_VPAD
end

--- Inline |A:...|a markup for Loot / Quest / Location source rows (My Plans, tracker, browse cards).
--- kinds: "loot" | "quest" | "location" | "class" (vendor/generic)
--- Drop uses Banker atlas (per UI direction). Default size = PLAN_SRC_ICON_LG.
local function PlanSourceIconMarkup(kind, size)
    size = size or PLAN_SRC_ICON_LG
    if kind == "loot" then
        return string.format("|A:Banker:%d:%d|a", size, size)
    elseif kind == "quest" then
        return string.format("|A:Islands-QuestTurnin:%d:%d|a", size, size)
    elseif kind == "location" then
        return string.format("|A:poi-islands-table:%d:%d|a", size, size)
    end
    return string.format("|A:Class:%d:%d|a", size, size)
end

ns.UI_PlanSourceIconMarkup = PlanSourceIconMarkup

local function SourcePrefixIconFromLabel(sourceType)
    if not sourceType or (issecretvalue and issecretvalue(sourceType)) then
        return PlanSourceIconMarkup("class") .. " "
    end
    local st = string.lower(sourceType)
    if st:match("quest") then
        return PlanSourceIconMarkup("quest") .. " "
    elseif st:match("drop") or st:match("loot") then
        return PlanSourceIconMarkup("loot") .. " "
    elseif st:match("location") or st:match("zone") then
        return PlanSourceIconMarkup("location") .. " "
    end
    return PlanSourceIconMarkup("class") .. " "
end

local function IsPlaceholderSourceText(sourceText)
    if type(sourceText) ~= "string" then return true end
    if issecretvalue and issecretvalue(sourceText) then return true end
    local s = sourceText:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return true end
    local unknownSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
    local sourceUnknown = (ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown"
    local sourceNotAvailable = (ns.L and ns.L["SOURCE_NOT_AVAILABLE"]) or "Source information not available"
    return s == "Unknown" or s == unknownSource or s == sourceUnknown or s == sourceNotAvailable or s == "Legacy"
end

-- Body text margins (match TOPLEFT 10 / RIGHT -30 used across plan cards)
local PLAN_CARD_BODY_LEFT = 10
local PLAN_CARD_BODY_RIGHT_INSET = 30
local PLAN_CARD_CONTENT_TOP = 60
local PLAN_CARD_BOTTOM_RESERVE = 38
local ACHIEVEMENT_CARD_MIN_HEIGHT = 96

local function PlanCardBodyTextWidth(card)
    local w = card:GetWidth() or 200
    return math.max(48, w - PLAN_CARD_BODY_LEFT - PLAN_CARD_BODY_RIGHT_INSET)
end

--[[
    Create base card structure
    @param parent Frame - Parent container
    @param plan table - Plan data
    @param progress table - Plan progress data
    @param layoutManager table - CardLayoutManager instance
    @param col number - Column index (0-based)
    @param cardHeight number - Base card height
    @param cardWidth number - Card width
    @return Frame - Created card frame
]]
function PlanCardFactory:CreateBaseCard(parent, plan, progress, layoutManager, col, cardHeight, cardWidth)
    if not parent or not plan then
        return nil, nil, nil
    end
    
    local card = CreateCard(parent, cardHeight)
    if not card then
        return nil, nil, nil
    end
    
    if cardWidth then
        card:SetWidth(cardWidth)
    end
    card:EnableMouse(true)
    
    -- Add to layout manager
    if layoutManager then
        CardLayoutManager:AddCard(layoutManager, card, col, cardHeight)
    end
    
    -- Store original height for expand/collapse
    card.originalHeight = cardHeight
    card.plan = plan
    card.progress = progress
    
    -- Initialize expanded state
    local cardKey = "plan_" .. plan.id
    card.cardKey = cardKey
    if not ns.expandedCards then
        ns.expandedCards = {}
    end
    card.isExpanded = ns.expandedCards[cardKey] or false
    card.expandedContent = nil
    
    -- Apply visuals (accent border for My Plans cards)
    local COLORS = ns.UI_COLORS or { accent = { 0.5, 0.4, 0.7 } }
    if ApplyVisuals then
        local borderColor = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 }
        ApplyVisuals(card, {0.08, 0.08, 0.10, 1}, borderColor)
    end
    
    -- Apply highlight effect (safe check for Factory)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(card)
    end
    
    -- Icon border frame for positioning reference (using Factory pattern)
    local iconBorder = ns.UI.Factory:CreateContainer(card, 46, 46)
    iconBorder:SetPoint("TOPLEFT", 10, -10)
    iconBorder:EnableMouse(false)
    card.iconBorder = iconBorder
    
    -- Determine icon: resolve from WoW API first, then fallback chain
    local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
    local WarbandNexus = ns.WarbandNexus
    local apiIcon = (WarbandNexus and WarbandNexus.GetResolvedPlanIcon) and WarbandNexus:GetResolvedPlanIcon(plan) or nil
    local iconTexture = apiIcon or plan.iconAtlas or plan.icon
    local iconIsAtlas = false

    -- Determine atlas flag based on icon source (using centralized Utilities helper)
    if apiIcon then
        if type(apiIcon) == "number" then
            iconIsAtlas = false
        elseif plan.iconIsAtlas then
            iconIsAtlas = true
        elseif plan.type == "custom" and plan.icon and plan.icon ~= "" then
            iconIsAtlas = true
        elseif ns.Utilities:IsAtlasName(apiIcon) then
            iconIsAtlas = true
        else
            iconIsAtlas = false
        end
    elseif plan.iconAtlas then
        iconIsAtlas = true
    elseif plan.type == "custom" and plan.icon and plan.icon ~= "" then
        iconIsAtlas = true
    else
        iconIsAtlas = plan.iconIsAtlas or false
    end

    -- Fallback: empty, nil, or blank icon → question mark
    if not iconTexture or iconTexture == "" then
        iconTexture = FALLBACK_ICON
        iconIsAtlas = false
    end
    
    local iconFrameObj = CreateIcon(card, iconTexture, 42, iconIsAtlas, nil, false)
    if iconFrameObj then
        iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
        iconFrameObj:EnableMouse(false)
    end

    -- (WN circular badge on the achievement icon was removed per user request — the To-Do already
    -- conveys this is "your" plan; the badge added visual noise inside the addon.)

    -- Completed state: green-tint name only (checkmark removed per design decision)
    
    -- Name text (use larger font for all cards)
    local nameText = FontManager:CreateFontString(card, "title", "OVERLAY")
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
    local P = ns.PLAN_UI_COLORS or {}
    local nameColor = (progress and progress.collected) and (P.completed or "|cff44ff44") or (P.incomplete or "|cffffffff")
    
    -- Resolve localized name from API (falls back to stored plan.name)
    local resolvedName = (WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    local displayName = FormatTextNumbers(resolvedName)
    
    nameText:SetText(nameColor .. displayName .. "|r")
    nameText:SetJustifyH("LEFT")
    -- Allow up to 2 lines so long titles wrap rather than clip in narrow cards.
    nameText:SetWordWrap(true)
    nameText:SetNonSpaceWrap(false)
    nameText:SetMaxLines(2)
    nameText:EnableMouse(false)
    card.nameText = nameText
    card.planNameText = nameText  -- Store reference for overflow checking
    
    -- Wowhead + optional chat link (top-right of name row; name truncates to their left)
    local CDL = ns.CollectionsDetailHeaderLayout or {}
    local whW = CDL.WOWHEAD_SIZE or ns.PLAN_CARD_WOWHEAD_SIZE or 18
    local whTop = CDL.CARD_WOWHEAD_TOP_OFFSET or 10
    local whInset = (ns.GetPlanCardWowheadRightInset and ns.GetPlanCardWowheadRightInset(plan.type)) or 56
    local nameGap = ns.PLAN_CARD_NAME_TO_WOWHEAD_GAP or 6
    local LINK_GAP = 4

    local wowheadEntityType, wowheadID
    if plan.type == "mount" then
        wowheadEntityType = "mount"
        if plan.mountID and C_MountJournal and C_MountJournal.GetMountInfoByID then
            local _, sid = C_MountJournal.GetMountInfoByID(plan.mountID)
            if sid and sid > 0 then wowheadID = sid end
        end
    elseif plan.type == "pet" then
        wowheadEntityType, wowheadID = "pet", plan.speciesID
    elseif plan.type == "toy" then
        wowheadEntityType, wowheadID = "toy", plan.itemID
    elseif plan.type == "achievement" then
        wowheadEntityType, wowheadID = "achievement", plan.achievementID
    elseif plan.type == "illusion" then
        wowheadEntityType, wowheadID = "illusion", plan.illusionID or plan.itemID
    elseif plan.type == "title" then
        wowheadEntityType, wowheadID = "title", plan.titleID
    end

    if wowheadEntityType and wowheadID and wowheadID > 0 then
        local whBtn = CreateFrame("Button", nil, card)
        whBtn:SetSize(whW, whW)
        whBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -whInset, -whTop)
        card.wowheadBtn = whBtn
        whBtn:SetNormalAtlas("socialqueuing-icon-eye")
        whBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        whBtn:SetFrameLevel(card:GetFrameLevel() + 5)
        whBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine((ns.L and ns.L["WOWHEAD_LABEL"]) or "Wowhead", 1, 0.82, 0)
            GameTooltip:AddLine((ns.L and ns.L["CLICK_TO_COPY_LINK"]) or "Click to copy link", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        whBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local capturedType, capturedID = wowheadEntityType, wowheadID
        whBtn:SetScript("OnClick", function(self)
            if ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                ns.UI.Factory:ShowWowheadCopyURL(capturedType, capturedID, self)
            end
        end)
    end

    if WarbandNexus.PlanSupportsChatLink and WarbandNexus:PlanSupportsChatLink(plan) then
        local linkBtn = CreateFrame("Button", nil, card)
        linkBtn:SetSize(whW, whW)
        if card.wowheadBtn then
            linkBtn:SetPoint("TOPRIGHT", card.wowheadBtn, "TOPLEFT", -LINK_GAP, 0)
        else
            linkBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -whInset, -whTop)
        end
        linkBtn:SetFrameLevel(card:GetFrameLevel() + 5)
        linkBtn:SetNormalTexture("Interface\\CHATFRAME\\UI-ChatIcon-Chat")
        linkBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        local capPlan = plan
        linkBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local L = ns.L
            GameTooltip:AddLine((L and L["PLAN_CHAT_LINK_TITLE"]) or "Chat link", 1, 0.82, 0)
            GameTooltip:AddLine((L and L["PLAN_CHAT_LINK_HINT"]) or "Click to insert into chat", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        linkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        linkBtn:SetScript("OnClick", function()
            if WarbandNexus.InsertPlanChatLink then
                WarbandNexus:InsertPlanChatLink(capPlan)
            end
        end)
        card.chatLinkBtn = linkBtn
    end

    local anchorNameRight = card.chatLinkBtn or card.wowheadBtn
    if anchorNameRight then
        nameText:SetPoint("RIGHT", anchorNameRight, "LEFT", -nameGap, 0)
    else
        nameText:SetPoint("RIGHT", card, "RIGHT", -(whInset + whW + nameGap), 0)
    end

    -- Show icon and card after full setup (prevents flickering)
    if iconFrameObj then
        iconFrameObj:Show()
    end
    card:Show()
    
    return card, iconBorder, nameText
end

--[[
    Create type badge (for non-achievement cards)
    @param card Frame - Card frame
    @param plan table - Plan data
    @param nameText Frame - Name text frame to anchor below
    @return Frame - Type badge text frame
]]
function PlanCardFactory:CreateTypeBadge(card, plan, nameText)
    if not card or not plan then
        return nil
    end
    
    -- Use nameText if provided, otherwise use card.nameText
    local anchorFrame = nameText or card.nameText
    if not anchorFrame then
        -- Fallback: use fixed position
        anchorFrame = card
    end
    
    local typeName = TYPE_NAMES[plan.type] or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    local COLORS = ns.UI_COLORS
    local typeColor = TYPE_COLORS[plan.type] or {0.6, 0.6, 0.6}
    -- Use accent color for custom and weekly_vault
    if plan.type == "custom" or plan.type == "weekly_vault" then
        typeColor = COLORS and COLORS.accent or {1, 0.2, 0.2}
    end
    local typeIconAtlas = TYPE_ICONS[plan.type]
    
    -- Create icon frame if available
    local iconFrame = nil
    if typeIconAtlas then
        iconFrame = ns.UI.Factory:CreateContainer(card, 20, 20)
        if anchorFrame == card then
            iconFrame:SetPoint("TOPLEFT", 10, -60)
        else
            iconFrame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
        end
        iconFrame:EnableMouse(false)
        
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
            iconFrame:Show()  -- Show after setup
        end
    end
    
    -- Create type badge text (ALWAYS create, even if anchor is card)
    local typeBadge = FontManager:CreateFontString(card, "subtitle", "OVERLAY")
    if iconFrame then
        typeBadge:SetPoint("LEFT", iconFrame, "RIGHT", 4, 0)
    else
        if anchorFrame == card then
            typeBadge:SetPoint("TOPLEFT", 10, -60)
        else
            typeBadge:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
        end
    end
    typeBadge:SetPoint("RIGHT", card, "RIGHT", -10, 0)  -- Prevent overflow
    typeBadge:SetJustifyH("LEFT")
    typeBadge:SetWordWrap(false)
    typeBadge:SetMaxLines(1)
    typeBadge:SetText(string.format("|cff%02x%02x%02x%s|r", 
        typeColor[1]*255, typeColor[2]*255, typeColor[3]*255,
        typeName))
    typeBadge:EnableMouse(false)
    
    return typeBadge
end

--[[
    Create achievement points badge
    @param card Frame - Card frame
    @param plan table - Plan data
    @param nameText Frame - Name text frame to anchor below
    @return Frame - Points text frame
]]
function PlanCardFactory:CreateAchievementPointsBadge(card, plan, nameText)
    local typeColor = TYPE_COLORS.achievement

    local shieldFrame = ns.UI.Factory:CreateContainer(card, 20, 20)
    shieldFrame:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
    card.pointsBadge = shieldFrame
    shieldFrame:EnableMouse(false)
    
    local shieldIcon = shieldFrame:CreateTexture(nil, "OVERLAY")
    shieldIcon:SetAllPoints()
    local shieldSuccess = pcall(function()
        shieldIcon:SetAtlas("UI-Achievement-Shield-NoPoints", false)
    end)
    if not shieldSuccess then
        shieldIcon:Hide()
    end
    shieldIcon:SetSnapToPixelGrid(false)
    shieldIcon:SetTexelSnappingBias(0)
    
    local pointsText = FontManager:CreateFontString(card, "subtitle", "OVERLAY")
    pointsText:SetPoint("LEFT", shieldFrame, "RIGHT", 4, 0)
    pointsText:SetPoint("RIGHT", card, "RIGHT", -10, 0)  -- Prevent overflow
    pointsText:SetJustifyH("LEFT")
    pointsText:SetWordWrap(false)
    pointsText:SetMaxLines(1)
    if plan.points then
        pointsText:SetText(string.format("|cff%02x%02x%02x" .. ((ns.L and ns.L["POINTS_FORMAT"]) or "%d Points") .. "|r", 
            typeColor[1]*255, typeColor[2]*255, typeColor[3]*255,
            plan.points))
    end
    pointsText:EnableMouse(false)
    
    return pointsText
end

--[[
    Create source information display
    @param card Frame - Card frame
    @param plan table - Plan data
    @param line3Y number - Y offset for line 3
    @return Frame - Last text element created
]]
function PlanCardFactory:CreateSourceInfo(card, plan, line3Y)
    local sources = {}
    -- Mount/Pet: when source is empty/placeholder, resolve from API so My Plans matches browser.
    if (plan.type == "mount" or plan.type == "pet") and IsPlaceholderSourceText(plan.source) and WarbandNexus and WarbandNexus.GetPlanDisplaySource then
        local resolved = WarbandNexus:GetPlanDisplaySource(plan)
        if resolved and resolved ~= "" then
            plan.source = resolved
        end
    end
    -- For toys: if stored source is generic/unreliable, resolve from metadata so Plans shows correct source only.
    if plan.type == "toy" and plan.itemID and WarbandNexus and WarbandNexus.ResolveCollectionMetadata then
        local function reliable(s)
            if WarbandNexus.IsReliableToySource then
                return WarbandNexus:IsReliableToySource(s)
            end
            return s and s ~= ""
        end
        if not reliable(plan.source) then
            local meta = WarbandNexus:ResolveCollectionMetadata("toy", plan.itemID)
            if meta and reliable(meta.source) then
                plan.source = meta.source
            end
        end
    end
    -- Safely parse source
    if plan.source and type(plan.source) == "string" and plan.source ~= "" then
        if WarbandNexus and WarbandNexus.ParseMultipleSources then
            local success, result = pcall(function()
                return WarbandNexus:ParseMultipleSources(plan.source)
            end)
            if success and result and #result > 0 then
                sources = result
            end
        end
    end
    
    local lastTextElement = nil
    local currentY = line3Y
    
    -- Show sources (collapsed: only first source, expanded: all sources)
    -- Store sources in card for expand functionality
    card._sources = sources
    card._planBodyFallbackFS = nil
    
    -- CRITICAL: Restore source expansion state from persistent storage (like achievement cards)
    if not card.cardKey then
        card.cardKey = "plan_" .. (plan.id or "unknown")
    end
    if not ns.expandedCards then
        ns.expandedCards = {}
    end
    -- Use separate key for source expansion state (non-achievement cards)
    local sourceExpandKey = card.cardKey .. "_source"
    if card._isSourceExpanded == nil then
        -- Restore from persistent storage
        card._isSourceExpanded = ns.expandedCards[sourceExpandKey] or false
    end
    -- CRITICAL: Ensure state is boolean (not nil) before using it
    if type(card._isSourceExpanded) ~= "boolean" then
        card._isSourceExpanded = false
    end
    
    -- Calculate if content exceeds card height
    local originalHeight = card.originalHeight or 130
    local maxContentHeight = originalHeight - 60  -- Reserve space for icon, name, etc.
    local estimatedContentHeight = 0
    
    if #sources > 0 then
        -- Estimate height needed for all sources
        local estRow = math.max(22, PLAN_SRC_ICON_LG + 8)
        for i, source in ipairs(sources) do
            if source.vendor or source.npc or source.quest then
                estimatedContentHeight = estimatedContentHeight + estRow
            end
            if source.zone then
                estimatedContentHeight = estimatedContentHeight + estRow
            end
            if i < #sources then
                estimatedContentHeight = estimatedContentHeight + PLAN_SRC_ROW_VPAD
            end
        end
        
        -- If content exceeds card height, enable expand/collapse
        local needsExpand = estimatedContentHeight > maxContentHeight
        
        -- CRITICAL: If expand button exists, content definitely exceeds card height
        -- Set _needsExpand flag if expand button exists
        if card._sourceExpandButton then
            card._needsExpand = true
        elseif card._needsExpand == nil then
            -- Store needsExpand flag for later use (set by SetupSourceExpandHandler)
            card._needsExpand = needsExpand
        end
        
        -- In collapsed view, show only first source if content exceeds card height
        -- CRITICAL: Use _needsExpand flag or expand button existence to determine collapse state
        local sourcesToShow
        
        -- Determine if we should collapse (show only first source)
        -- CRITICAL: If expand button exists, we ALWAYS need to respect expansion state
        -- Priority: 1) If expand button exists, ALWAYS use expansion state (most reliable)
        --           2) Otherwise, use _needsExpand flag or calculated needsExpand
        local shouldCollapse = false
        
        -- CRITICAL: Ensure _isSourceExpanded is boolean before checking
        local isExpanded = (card._isSourceExpanded == true)
        
        -- CRITICAL: If expand button exists, content definitely exceeds card height
        -- We MUST respect the expansion state - if collapsed, show only first source
        -- This is the MOST RELIABLE check - if button exists, we know content exceeds
        if card._sourceExpandButton then
            -- Expand button exists = content definitely exceeds card height
            -- Collapse if not expanded (show only first source)
            shouldCollapse = not isExpanded
        elseif card._needsExpand == true then
            -- _needsExpand flag is explicitly set to true (from SetupSourceExpandHandler)
            shouldCollapse = not isExpanded
        elseif needsExpand then
            -- Calculated needsExpand (first time CreateSourceInfo is called, before SetupSourceExpandHandler)
            shouldCollapse = not isExpanded
        end
        
        
        -- CRITICAL: Always respect shouldCollapse if expand button exists
        -- This ensures that after expand->collapse, we show only first source
        -- FORCE collapse if expand button exists and not expanded
        if card._sourceExpandButton and not isExpanded then
            -- Expand button exists and collapsed - MUST show only first source
            sourcesToShow = {sources[1]}
        elseif shouldCollapse and #sources > 0 then
            -- Content exceeds card height and collapsed - show only first source
            sourcesToShow = {sources[1]}
        else
            -- Expanded or content fits - show all sources
            sourcesToShow = sources
        end
        
        
        -- Create source container frame (similar to achievement's expandedContent)
        -- CRITICAL: Destroy and recreate container to ensure clean state
        -- This is more reliable than trying to clear all children
        if card._sourceContainer then
            -- Destroy old container completely
            local oldContainer = card._sourceContainer
            local bin = ns.UI_RecycleBin
            -- Clear all children first
            for i = oldContainer:GetNumChildren(), 1, -1 do
                local child = select(i, oldContainer:GetChildren())
                if child then
                    child:Hide()
                    child:ClearAllPoints()
                    if bin then child:SetParent(bin) else child:SetParent(nil) end
                end
            end
            oldContainer:Hide()
            oldContainer:ClearAllPoints()
            if bin then oldContainer:SetParent(bin) else oldContainer:SetParent(nil) end
            card._sourceContainer = nil
        end
        
        -- Create fresh container (using Factory pattern)
        local sourceContainer = ns.UI.Factory:CreateContainer(card)
        sourceContainer:SetPoint("TOPLEFT", PLAN_CARD_BODY_LEFT, line3Y)
        sourceContainer:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
        sourceContainer:SetHeight(1)  -- Will be calculated dynamically
        card._sourceContainer = sourceContainer
        
        
        -- Create source elements inside container
        -- CRITICAL: Ensure container is visible before creating elements
        card._sourceContainer:Show()
        local containerY = 0
        
        
        for i, source in ipairs(sourcesToShow) do
            -- Vendor or Drop
            if source.vendor then
                local vendorText = FontManager:CreateFontString(card._sourceContainer, "body", "OVERLAY")
                vendorText._isSourceElement = true
                vendorText:SetPoint("TOPLEFT", 0, containerY)
                vendorText:SetPoint("RIGHT", 0, 0)
                vendorText:SetText(PlanSourceIconMarkup("class") .. " |cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["VENDOR_LABEL"]) or "Vendor:") .. "|r |cffffffff" .. source.vendor .. "|r")
                vendorText:SetJustifyH("LEFT")
                vendorText:SetWordWrap(true)
                vendorText:SetNonSpaceWrap(false)
                if not card._isSourceExpanded then
                    vendorText:SetMaxLines(4)
                else
                    vendorText:SetMaxLines(10)
                end
                lastTextElement = vendorText
                containerY = PlanSourceAdvanceY(containerY, vendorText, true)
            elseif source.npc then
                local dropText = FontManager:CreateFontString(card._sourceContainer, "body", "OVERLAY")
                dropText._isSourceElement = true
                dropText:SetPoint("TOPLEFT", 0, containerY)
                dropText:SetPoint("RIGHT", 0, 0)
                local npcColor = "ffffffff"
                local sourceDB = ns.CollectibleSourceDB
                if sourceDB and sourceDB.lockoutNpcNames and sourceDB.lockoutQuests then
                    local npcID = sourceDB.lockoutNpcNames[source.npc]
                    if npcID then
                        local questData = sourceDB.lockoutQuests[npcID]
                        if questData then
                            local questIDs = type(questData) == "table" and questData or { questData }
                            for qi = 1, #questIDs do
                                if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questIDs[qi]) then
                                    npcColor = "ff666666"
                                    break
                                end
                            end
                        end
                    end
                end
                dropText:SetText(PlanSourceIconMarkup("loot") .. " |cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["DROP_LABEL"]) or "Drop:") .. "|r |c" .. npcColor .. " " .. source.npc .. "|r")
                dropText:SetJustifyH("LEFT")
                dropText:SetWordWrap(true)
                dropText:SetNonSpaceWrap(false)
                if not card._isSourceExpanded then
                    dropText:SetMaxLines(4)
                else
                    dropText:SetMaxLines(10)
                end
                lastTextElement = dropText
                containerY = PlanSourceAdvanceY(containerY, dropText, true)
            elseif source.quest then
                local P = ns.PLAN_UI_COLORS or {}
                local questLabel = NormalizeColonLabelSpacing((ns.L and ns.L["QUEST_LABEL"]) or "Quest:")
                local questText = FontManager:CreateFontString(card._sourceContainer, "body", "OVERLAY")
                questText._isSourceElement = true
                questText:SetPoint("TOPLEFT", 0, containerY)
                questText:SetPoint("RIGHT", 0, 0)
                questText:SetText(PlanSourceIconMarkup("quest") .. " " .. (P.sourceLabel or "|cff99ccff") .. questLabel .. "|r" .. (P.body or "|cffffffff") .. source.quest .. "|r")
                questText:SetJustifyH("LEFT")
                questText:SetWordWrap(true)
                questText:SetNonSpaceWrap(false)
                if not card._isSourceExpanded then
                    questText:SetMaxLines(4)
                else
                    questText:SetMaxLines(10)
                end
                lastTextElement = questText
                containerY = PlanSourceAdvanceY(containerY, questText, true)
            end
            
            -- Location (Zone) — append difficulty label for mounts (consistent white; avoid duplication)
            if source.zone then
                local zoneDiffLabel = ""
                if plan and plan.type == "mount" and WarbandNexus and WarbandNexus.GetDropDifficulty then
                    local mountID = plan.mountID
                    if mountID then
                        local diff = WarbandNexus:GetDropDifficulty("mount", mountID)
                        local z = source.zone
                        local zSafe = z and type(z) == "string" and not (issecretvalue and issecretvalue(z))
                        local dSafe = diff and not (issecretvalue and issecretvalue(diff))
                        if dSafe and zSafe then
                            -- Don't duplicate: zone may already contain "(Mythic)" from API
                            if not z:find("(" .. diff .. ")", 1, true) then
                                local bodyColor = (ns.PLAN_UI_COLORS or {}).body or "|cffffffff"
                                zoneDiffLabel = " " .. bodyColor .. "(" .. diff .. ")|r"
                            end
                        end
                    end
                end
                local locationText = FontManager:CreateFontString(card._sourceContainer, "body", "OVERLAY")
                locationText._isSourceElement = true
                locationText:SetPoint("TOPLEFT", 0, containerY)
                locationText:SetPoint("RIGHT", 0, 0)
                locationText:SetText(PlanSourceIconMarkup("location") .. " |cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["LOCATION_LABEL"]) or "Location:") .. "|r |cffffffff" .. source.zone .. "|r" .. zoneDiffLabel)
                locationText:SetJustifyH("LEFT")
                locationText:SetWordWrap(true)
                locationText:SetNonSpaceWrap(false)
                if not card._isSourceExpanded then
                    locationText:SetMaxLines(5)
                else
                    locationText:SetMaxLines(12)
                end
                lastTextElement = locationText
                containerY = PlanSourceAdvanceY(containerY, locationText, true)
            end
            
            -- Add spacing between sources
            if i < #sourcesToShow then
                containerY = containerY - 2
            end
        end
        
        -- Update container height and visibility based on expansion state
        if card._sourceContainer then
            card._sourceContainer:SetHeight(math.abs(containerY))
            -- Container is always visible, content (sourcesToShow) changes based on expansion state
            -- This mimics achievement's expandedContent behavior
        end
        
        -- Return container as lastTextElement for anchoring purposes
        if card._sourceContainer and lastTextElement then
            lastTextElement = card._sourceContainer
        end
        
        -- Expand indicator is handled by SetupSourceExpandHandler
        -- Don't create it here, it will be created as a button
    end
    
    -- Fallback: If no structured sources found, show raw source text
    if #sources == 0 and not lastTextElement then
        local rawText = plan.source or ""
        if type(rawText) ~= "string" or (issecretvalue and issecretvalue(rawText)) then
            rawText = ""
        elseif WarbandNexus and WarbandNexus.CleanSourceText then
            local success, cleaned = pcall(function()
                return WarbandNexus:CleanSourceText(rawText)
            end)
            if success and cleaned and type(cleaned) == "string" and not (issecretvalue and issecretvalue(cleaned)) then
                rawText = cleaned
            end
        end
        
        -- Normalize whitespace
        rawText = rawText:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        
        -- If still empty or "Unknown", show a meaningful message
        if rawText == "" or rawText == "Unknown" or rawText == ((ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source") then
            rawText = (ns.L and ns.L["SOURCE_NOT_AVAILABLE"]) or "Source information not available"
        end
        
        local sourceText = FontManager:CreateFontString(card, "body", "OVERLAY")
        sourceText:SetPoint("TOPLEFT", PLAN_CARD_BODY_LEFT, currentY)
        sourceText:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
        
        -- Check if text already has a source type prefix
        local sourceType, sourceDetail = rawText:match("^([^:]+:%s*)(.*)$")
        
        if sourceType and sourceDetail and sourceDetail ~= "" then
            -- Text already has source type prefix
            sourceText:SetText(SourcePrefixIconFromLabel(sourceType) .. "|cff99ccff" .. sourceType .. "|r|cffffffff" .. sourceDetail .. "|r")
        else
            -- No source type prefix, add "Source:" label
            sourceText:SetText(PlanSourceIconMarkup("class") .. " |cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:") .. "|r |cffffffff" .. rawText .. "|r")
        end
        sourceText:SetJustifyH("LEFT")
        sourceText:SetWordWrap(true)
        sourceText:SetMaxLines(10)
        sourceText:SetNonSpaceWrap(false)
        card._planBodyFallbackFS = sourceText
        lastTextElement = sourceText
    end
    
    
    if not lastTextElement then
        local placeholderText = FontManager:CreateFontString(card, "body", "OVERLAY")
        placeholderText:SetPoint("TOPLEFT", PLAN_CARD_BODY_LEFT, line3Y)
        placeholderText:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
        placeholderText:SetText(PlanSourceIconMarkup("class") .. " |cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:") .. "|r |cffffffff" .. ((ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source") .. "|r")
        placeholderText:SetJustifyH("LEFT")
        placeholderText:SetWordWrap(true)
        placeholderText:SetMaxLines(6)
        placeholderText:SetNonSpaceWrap(false)
        card._planBodyFallbackFS = placeholderText
        lastTextElement = placeholderText
    end

    local Factory = ns.UI.Factory
    local tryCountTypes = { mount = "mountID", pet = "speciesID", toy = "itemID", illusion = "sourceID" }
    local idKey = tryCountTypes[plan.type]
    local collectibleID = idKey and (plan[idKey] or (plan.type == "illusion" and plan.illusionID))
    if collectibleID and Factory and Factory.CreateTryCountClickable and WarbandNexus then
        local resolvedName = (WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name
        local row = card.tryCountClickable
        if not row then
            local tryOpts = { height = 18, frameLevelOffset = 5, fontCategory = "body" }
            if card._wnTryCountClickableOptions then
                for k, v in pairs(card._wnTryCountClickableOptions) do
                    tryOpts[k] = v
                end
            end
            row = Factory:CreateTryCountClickable(card, tryOpts)
            row:SetSize(120, 18)
            card.tryCountClickable = row
        end
        do
            local gap = 8
            local nameGap = ns.PLAN_CARD_NAME_TO_WOWHEAD_GAP or 6
            local whW = ns.PLAN_CARD_WOWHEAD_SIZE or 18
            local anchorForTry = card.chatLinkBtn or card.wowheadBtn
            if anchorForTry then
                row:SetPoint("TOPRIGHT", anchorForTry, "TOPLEFT", -gap, 0)
            else
                local whInset = (ns.GetPlanCardWowheadRightInset and ns.GetPlanCardWowheadRightInset(plan.type)) or 56
                row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(whInset + whW + gap), -10)
            end
            -- Try sits on the name row, immediately to the right of the title (before chat/Wowhead)
            if card.nameText then
                card.nameText:SetPoint("RIGHT", row, "LEFT", -nameGap, 0)
            end
        end
        card.tryCountText = row.text
        row:WnUpdateTryCount(plan.type, collectibleID, resolvedName)
    elseif card.tryCountClickable then
        card.tryCountClickable:Hide()
        if card.nameText then
            local nameGap = ns.PLAN_CARD_NAME_TO_WOWHEAD_GAP or 6
            local anchorNameRight = card.chatLinkBtn or card.wowheadBtn
            if anchorNameRight then
                card.nameText:SetPoint("RIGHT", anchorNameRight, "LEFT", -nameGap, 0)
            else
                local whInset = (ns.GetPlanCardWowheadRightInset and ns.GetPlanCardWowheadRightInset(plan.type)) or 56
                local whW = ns.PLAN_CARD_WOWHEAD_SIZE or 18
                card.nameText:SetPoint("RIGHT", card, "RIGHT", -(whInset + whW + nameGap), 0)
            end
        end
    end

    return lastTextElement
end

--[[
    Create expandable content frame
    @param card Frame - Card frame
    @param anchorFrame Frame - Frame to anchor below
    @return Frame - Expanded content frame
]]
function PlanCardFactory:CreateExpandableContent(card, anchorFrame)
    local expandedContent = ns.UI.Factory:CreateContainer(card)
    -- Anchor to BOTTOM of anchorFrame with proper spacing (negative Y = down)
    expandedContent:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -8)
    expandedContent:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
    -- Don't set height here - it will be calculated dynamically based on content
    -- But set a minimum height to ensure frame exists
    expandedContent:SetHeight(1)
    card.expandedContent = expandedContent
    expandedContent:Hide()
    
    return expandedContent
end

--[[
    Create unified expand/collapse button for all card types
    @param card Frame - Card frame
    @param isExpanded boolean - Current expansion state
    @return Button - Expand button frame
]]
function PlanCardFactory:CreateExpandButton(card, isExpanded)
    -- Remove existing expand button if any
    if card._expandButton then
        local bin = ns.UI_RecycleBin
        card._expandButton:Hide()
        if bin then card._expandButton:SetParent(bin) else card._expandButton:SetParent(nil) end
        card._expandButton = nil
    end
    
    -- Create expand button (using Factory pattern, 20x20, same size as delete button)
    local expandButton = ns.UI.Factory:CreateButton(card, 20, 20, true)  -- noBorder=true
    expandButton:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 10)
    expandButton:EnableMouse(true)
    
    -- Create arrow icon texture
    local arrowTexture = expandButton:CreateTexture(nil, "OVERLAY")
    arrowTexture:SetAllPoints(expandButton)
    if isExpanded then
        arrowTexture:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover", false)
    else
        arrowTexture:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover", false)
    end
    expandButton.arrowTexture = arrowTexture
    
    card._expandButton = expandButton
    return expandButton
end

--[[
    Update expand button icon based on expansion state
    @param card Frame - Card frame
    @param isExpanded boolean - Current expansion state
]]
function PlanCardFactory:UpdateExpandButtonIcon(card, isExpanded)
    if card._expandButton and card._expandButton.arrowTexture then
        if isExpanded then
            card._expandButton.arrowTexture:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover", false)
        else
            card._expandButton.arrowTexture:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover", false)
        end
    end
end

--[[
    Setup unified card click handler for expand/collapse
    @param card Frame - Card frame
    @param expandCallback function - Callback to execute on expand/collapse
]]
function PlanCardFactory:SetupCardClickHandler(card, expandCallback)
    -- Store original click handler if exists (Midnight: GetScript errors when no script set on Frame)
    local originalOnMouseUp = nil
    do
        local ok, res = pcall(function() return card:GetScript("OnMouseUp") end)
        if ok then originalOnMouseUp = res end
    end
    
    if not card.clickedOnRemoveBtn then
        card.clickedOnRemoveBtn = false
    end
    if not card.clickedOnExpandButton then
        card.clickedOnExpandButton = false
    end
    
    card:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        
        -- Check if click was on remove button
        if self.clickedOnRemoveBtn then
            self.clickedOnRemoveBtn = false
            -- Call original handler for remove button functionality
            if originalOnMouseUp then
                originalOnMouseUp(self, button)
            end
            return
        end
        
        -- Check if click was on expand button
        if self.clickedOnExpandButton then
            self.clickedOnExpandButton = false
            -- Expand button has its own OnClick handler, don't trigger card click
            return
        end
        
        -- If we get here, it's a card click (not remove or expand button)
        -- Trigger expand/collapse on card click
        if expandCallback then
            expandCallback(self)
        end
    end)
end

--[[
    Remeasure achievement card stacked text (word-wrap) and sync frame height with layout manager.
    opts.deferLayout: only ApplyCardGeometry; caller runs RecalculateAllPositions once (resize batch).
]]
function PlanCardFactory:ReflowAchievementCard(card, opts)
    if not card or not card.plan or card.plan.type ~= "achievement" then return end
    local deferLayout = opts and opts.deferLayout
    local L = ns.L
    local P = ns.PLAN_UI_COLORS or {}
    local labCol = P.infoLabel or "|cff88ff88"
    local bodyCol = P.body or "|cffffffff"
    local descLab = NormalizeColonLabelSpacing((L and L["DESCRIPTION_LABEL"]) or "Description:")

    -- Body text frames are anchored via LEFT/RIGHT to the card, so width auto-tracks card width.
    -- We force SetWidth(tw) too so GetStringHeight() returns the wrapped height in the same frame
    -- (anchor-driven width is lazy and can produce single-line height in synchronous reflow).
    local tw = PlanCardBodyTextWidth(card)
    if card.infoText then
        if card.fullDescription and card.fullDescription ~= "" then
            card.infoText:SetText(labCol .. descLab .. "|r " .. bodyCol .. FormatTextNumbers(card.fullDescription) .. "|r")
        end
        card.infoText:SetWordWrap(true)
        card.infoText:SetNonSpaceWrap(false)
        card.infoText:SetMaxLines(0)
        card.infoText:SetWidth(tw)
    end

    if card.progressLabel then
        card.progressLabel:SetWordWrap(true)
        -- Unlimited wrap so the full progress sentence is shown (some locales / long labels overflow MaxLines=4).
        card.progressLabel:SetMaxLines(0)
        card.progressLabel:SetWidth(tw)
    end

    if card.rewardTextFS then
        card.rewardTextFS:SetWordWrap(true)
        card.rewardTextFS:SetMaxLines(0)
        card.rewardTextFS:SetWidth(tw)
    end

    if card.requirementsHeader then
        card.requirementsHeader:SetWordWrap(true)
        card.requirementsHeader:SetMaxLines(0)
        card.requirementsHeader:SetWidth(tw)
    end

    -- Compute header bottom (icon row, name, points badge) so wrapped 2-line titles push body down.
    -- nameText is anchored LEFT to icon and RIGHT to action buttons, but the engine's anchor-driven
    -- width is lazy — synchronous GetStringHeight() can return single-line height even if the text
    -- visibly wraps. Force-set nameText width here so wrapped height is measured correctly.
    if card.nameText then
        local CDL = ns.CollectionsDetailHeaderLayout or {}
        local whW = CDL.WOWHEAD_SIZE or ns.PLAN_CARD_WOWHEAD_SIZE or 18
        local whInset = (ns.GetPlanCardWowheadRightInset and card.plan and ns.GetPlanCardWowheadRightInset(card.plan.type)) or 56
        local nameGap = ns.PLAN_CARD_NAME_TO_WOWHEAD_GAP or 6
        local LINK_GAP = 4
        local rightReserve = whInset + whW + nameGap
        if card.chatLinkBtn then rightReserve = rightReserve + whW + LINK_GAP end
        -- nameText TOPLEFT is at iconBorder TOPRIGHT(+10) → x ~= iconBorderX(10) + iconW(46) + 10 = 66
        local nameLeftX = 66
        local cw = card:GetWidth() or 200
        local nameW = math.max(60, cw - nameLeftX - rightReserve)
        card.nameText:SetWidth(nameW)
    end
    local nameH = (card.nameText and card.nameText:GetStringHeight()) or 14
    if not nameH or nameH < 14 then nameH = 14 end
    -- Derive header geometry from existing card children rather than hardcoded constants.
    local nameTopInset = 12  -- iconBorder y(-10) + nameText y(-2) relative to icon TOPRIGHT
    local headerH = nameTopInset + nameH
    if card.pointsBadge and card.pointsBadge:IsShown() then
        local bh = card.pointsBadge:GetHeight() or 20
        headerH = headerH + 2 + bh
    end
    -- Ensure header is at least as tall as the icon row (icon height + top inset).
    local iconBorderH = (card.iconBorder and card.iconBorder:GetHeight()) or 46
    local minHeader = 10 + iconBorderH
    if headerH < minHeader then headerH = minHeader end

    local h = headerH + 8  -- 8px gap before first body element
    local gap = 6
    local firstShown = true
    local function addFs(fs)
        if not fs or not fs:IsShown() then return end
        if not firstShown then
            h = h + gap
        end
        firstShown = false
        local sh = fs:GetStringHeight()
        if not sh or sh < 1 then
            sh = fs:GetHeight() or 14
        end
        h = h + math.max(sh, 12)
    end

    addFs(card.infoText)
    addFs(card.progressLabel)
    addFs(card.rewardTextFS)
    addFs(card.requirementsHeader)

    if card.isExpanded and card.expandedContent and card.expandedContent:IsShown() then
        h = h + 8 + math.max(card.expandedContent:GetHeight() or 1, 1)
    end

    h = h + PLAN_CARD_BOTTOM_RESERVE

    local newH = math.max(ACHIEVEMENT_CARD_MIN_HEIGHT, h)
    if deferLayout then
        CardLayoutManager:ApplyCardGeometry(card, newH)
    elseif card._layoutManager then
        CardLayoutManager:UpdateCardHeight(card, newH)
    else
        card:SetHeight(newH)
    end
end

--[[
    Remeasure mount/pet/toy/etc. source block height after width changes or wrap layout.
]]
function PlanCardFactory:ReflowSourcePlanCard(card, opts)
    if not card or not card.plan then return end
    local pt = card.plan.type
    if pt ~= "mount" and pt ~= "pet" and pt ~= "toy" and pt ~= "illusion" and pt ~= "title" and pt ~= "transmog" then
        return
    end
    local deferLayout = opts and opts.deferLayout
    local tw = PlanCardBodyTextWidth(card)
    local bodyH = 0

    if card._sourceContainer and card._sourceContainer:IsShown() then
        card._sourceContainer:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
        local sumH = 0
        for i = 1, card._sourceContainer:GetNumChildren() do
            local ch = select(i, card._sourceContainer:GetChildren())
            if ch and ch:IsObjectType("FontString") and ch:IsShown() then
                ch:SetWidth(tw)
                sumH = sumH + math.max(ch:GetStringHeight(), 14) + 4
            end
        end
        sumH = math.max(sumH, 1)
        card._sourceContainer:SetHeight(sumH)
        bodyH = sumH
    elseif card._planBodyFallbackFS and card._planBodyFallbackFS:IsShown() then
        card._planBodyFallbackFS:SetWidth(tw)
        card._planBodyFallbackFS:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
        bodyH = math.max(card._planBodyFallbackFS:GetStringHeight(), 14)
    else
        bodyH = 18
    end

    local newH = math.max(card.originalHeight or 105, PLAN_CARD_CONTENT_TOP + bodyH + PLAN_CARD_BOTTOM_RESERVE)
    if deferLayout then
        CardLayoutManager:ApplyCardGeometry(card, newH)
    elseif card._layoutManager then
        CardLayoutManager:UpdateCardHeight(card, newH)
    else
        card:SetHeight(newH)
    end
end

--- Batch reflow after grid width changes (resize) — one masonry pass at the end.
function PlanCardFactory:ReflowAllPlanCards(layoutInstance)
    if not layoutInstance or not layoutInstance.cards then return end
    for i = 1, #layoutInstance.cards do
        local info = layoutInstance.cards[i]
        local c = info and info.card
        if c and c.plan then
            local t = c.plan.type
            if t == "achievement" then
                self:ReflowAchievementCard(c, { deferLayout = true })
            elseif t == "mount" or t == "pet" or t == "toy" or t == "illusion" or t == "title" or t == "transmog" then
                self:ReflowSourcePlanCard(c, { deferLayout = true })
            end
        end
    end
    CardLayoutManager:RecalculateAllPositions(layoutInstance)
end

--[[
    Main factory method - creates a plan card based on type
    @param parent Frame - Parent container
    @param plan table - Plan data
    @param progress table - Plan progress data
    @param layoutManager table - CardLayoutManager instance
    @param col number - Column index (0-based)
    @param cardHeight number - Base card height
    @param cardWidth number - Card width (optional)
    @param cardUIOptions table|nil e.g. { tryCountClickableOptions = { popupOnRightClick = false } } for To-Do List
    @return Frame - Created card frame
]]
function PlanCardFactory:CreateCard(parent, plan, progress, layoutManager, col, cardHeight, cardWidth, cardUIOptions)
    if not plan or not plan.type then
        return nil
    end
    
    -- Ensure progress is a table (not nil)
    if not progress then
        progress = {}
    end
    
    -- Create base card
    local card, iconBorder, nameText = self:CreateBaseCard(parent, plan, progress, layoutManager, col, cardHeight, cardWidth)
    
    if not card then
        return nil
    end

    if cardUIOptions and cardUIOptions.tryCountClickableOptions then
        card._wnTryCountClickableOptions = cardUIOptions.tryCountClickableOptions
    else
        card._wnTryCountClickableOptions = nil
    end
    
    -- Create type-specific content
    if plan.type == "achievement" then
        local success, err = pcall(function()
            self:CreateAchievementCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create achievement card: " .. tostring(err))
        end
    elseif plan.type == "mount" then
        local success, err = pcall(function()
            self:CreateMountCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create mount card: " .. tostring(err))
        end
    elseif plan.type == "pet" then
        local success, err = pcall(function()
            self:CreatePetCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create pet card: " .. tostring(err))
        end
    elseif plan.type == "toy" then
        local success, err = pcall(function()
            self:CreateToyCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create toy card: " .. tostring(err))
        end
    elseif plan.type == "illusion" then
        local success, err = pcall(function()
            self:CreateIllusionCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create illusion card: " .. tostring(err))
        end
    elseif plan.type == "title" then
        local success, err = pcall(function()
            self:CreateTitleCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create title card: " .. tostring(err))
        end
    elseif plan.type == "weekly_vault" then
        local success, err = pcall(function()
            self:CreateWeeklyVaultCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create weekly vault card: " .. tostring(err))
        end
    elseif plan.type == "daily_quests" then
        -- Daily quests handled separately in PlansUI
        -- Just return base card
    else
        -- Default card for other types
        local success, err = pcall(function()
            self:CreateDefaultCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create default card: " .. tostring(err))
        end
    end
    
    return card
end

--[[
    Create achievement card with expand functionality
]]
function PlanCardFactory:CreateAchievementCard(card, plan, progress, nameText)
    local P = ns.PLAN_UI_COLORS or {}
    -- Create points badge
    if plan.points then
        self:CreateAchievementPointsBadge(card, plan, nameText)
    end
    
    -- Parse source for achievement-specific display
    local rawText = plan.source or ""
    if type(rawText) ~= "string" or (issecretvalue and issecretvalue(rawText)) then
        rawText = ""
    elseif WarbandNexus.CleanSourceText then
        rawText = WarbandNexus:CleanSourceText(rawText)
    end
    
    local description, progressText = rawText:match("^(.-)%s*(Progress:%s*.+)$")
    
    -- ALWAYS prefer API description for achievements (ensures localization)
    if plan.achievementID then
        local success, _, _, _, _, _, _, _, achievementDescription = pcall(GetAchievementInfo, plan.achievementID)
        if success and achievementDescription and not (issecretvalue and issecretvalue(achievementDescription)) and achievementDescription ~= "" then
            description = achievementDescription
        end
    end
    
    -- Additional fallback: Check if plan has description field
    if (not description or description == "") and plan.description then
        local pd = plan.description
        if type(pd) == "string" and not (issecretvalue and issecretvalue(pd)) then
            description = pd
        end
    end
    
    -- Anchor body content below the name/badge row so wrapped 2-line titles don't overlap.
    -- Use separate TOP / LEFT / RIGHT anchors so X is card-relative (consistent inset) while Y follows the header.
    local headerAnchor = card.pointsBadge or nameText
    local lastTextElement = nil

    local function anchorBodyTop(fs, prev)
        if prev then
            fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
            fs:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
        else
            fs:SetPoint("TOP", headerAnchor, "BOTTOM", 0, -8)
            fs:SetPoint("LEFT", card, "LEFT", PLAN_CARD_BODY_LEFT, 0)
            fs:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
        end
    end

    -- Description: word-wrap to card width (no manual substring truncation — avoids false ellipsis when space remains)
    if description and not (issecretvalue and issecretvalue(description)) and description ~= "" then
        description = description:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        card.fullDescription = description

        local L = ns.L
        local labCol = P.infoLabel or "|cff88ff88"
        local bodyCol = P.body or "|cffffffff"
        local descLab = NormalizeColonLabelSpacing((L and L["DESCRIPTION_LABEL"]) or "Description:")
        local infoText = FontManager:CreateFontString(card, "body", "OVERLAY")
        anchorBodyTop(infoText, lastTextElement)
        infoText:SetText(labCol .. descLab .. "|r " .. bodyCol .. FormatTextNumbers(description) .. "|r")
        infoText:SetJustifyH("LEFT")
        infoText:SetWordWrap(true)
        infoText:SetMaxLines(0)
        infoText:SetNonSpaceWrap(false)
        card.infoText = infoText
        lastTextElement = infoText
    end

    -- Progress (calculate actual progress from achievement criteria)
    local progressLabel = FontManager:CreateFontString(card, "subtitle", "OVERLAY")
    anchorBodyTop(progressLabel, lastTextElement)
    progressLabel:SetJustifyH("LEFT")
    progressLabel:SetWordWrap(true)
    progressLabel:SetNonSpaceWrap(false)
    progressLabel:SetMaxLines(0)  -- Show full progress sentence — never truncate.
    card.progressLabel = progressLabel  -- Store for later update
    card.planAchievementID = plan.achievementID  -- Store for progress calculation
    
    -- Calculate progress on initial creation
    local achievementID = plan.achievementID
    if achievementID then
        local numCriteria = GetAchievementNumCriteria(achievementID)
        if numCriteria and numCriteria > 0 then
            local completedCount = 0
            local totalQuantity = 0
            local totalReqQuantity = 0
            local hasProgressBased = false
            
            for criteriaIndex = 1, numCriteria do
                local criteriaName, criteriaType, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, criteriaIndex)
                if criteriaName and criteriaName ~= "" then
                    if completed then
                        completedCount = completedCount + 1
                    end
                    if quantity and reqQuantity and reqQuantity > 0 then
                        totalQuantity = totalQuantity + (quantity or 0)
                        totalReqQuantity = totalReqQuantity + (reqQuantity or 0)
                        hasProgressBased = true
                    end
                end
            end
            
            local P2 = ns.PLAN_UI_COLORS or {}
            local progressColor = (completedCount == numCriteria) and (P2.progressFull or "|cff00ff00") or (P2.incomplete or "|cffffffff")
            if hasProgressBased and totalReqQuantity > 0 then
                local progressFmt = (ns.L and ns.L["PROGRESS_ON_FORMAT"]) or "You are %d / %d on the progress"
                local progressText = (P2.progressLabel or "|cffffcc00") .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r " .. progressColor .. string.format(progressFmt, totalQuantity, totalReqQuantity) .. "|r"
                progressLabel:SetText(FormatTextNumbers(progressText))
            else
                local reqFmt = (ns.L and ns.L["COMPLETED_REQ_FORMAT"]) or "You completed %d of %d total requirements"
                local progressText = (P2.progressLabel or "|cffffcc00") .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r " .. progressColor .. string.format(reqFmt, completedCount, numCriteria) .. "|r"
                progressLabel:SetText(FormatTextNumbers(progressText))
            end
        else
            progressLabel:SetText((ns.PLAN_UI_COLORS and ns.PLAN_UI_COLORS.progressLabel or "|cffffcc00") .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r")
        end
    else
        progressLabel:SetText((ns.PLAN_UI_COLORS and ns.PLAN_UI_COLORS.progressLabel or "|cffffcc00") .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r")
    end
    
    lastTextElement = progressLabel
    
    -- Reward
    local displayReward = plan.rewardText
    if (not displayReward or displayReward == "") and plan.achievementID and WarbandNexus.GetAchievementRewardInfo then
        local ri = WarbandNexus:GetAchievementRewardInfo(plan.achievementID)
        if ri then displayReward = ri.title or ri.itemName end
    end
    if displayReward and displayReward ~= "" then
        local rewardText = FontManager:CreateFontString(card, "small", "OVERLAY")
        anchorBodyTop(rewardText, lastTextElement)
        rewardText:SetText("|cff88ff88" .. NormalizeColonLabelSpacing((ns.L and ns.L["REWARD_LABEL"]) or "Reward:") .. "|r |cffffffff" .. displayReward .. "|r")
        rewardText:SetJustifyH("LEFT")
        rewardText:SetWordWrap(true)
        rewardText:SetMaxLines(0)  -- Reward text shown in full.
        rewardText:SetNonSpaceWrap(false)
        card.rewardTextFS = rewardText
        lastTextElement = rewardText
    end

    -- Requirements header
    local requirementsHeader = FontManager:CreateFontString(card, "subtitle", "OVERLAY")
    anchorBodyTop(requirementsHeader, lastTextElement)
    requirementsHeader:SetText("|cffffcc00" .. NormalizeColonLabelSpacing((ns.L and ns.L["REQUIREMENTS_LABEL"]) or "Requirements:") .. "|r ...")
    requirementsHeader:SetJustifyH("LEFT")
    requirementsHeader:SetTextColor(1, 1, 1)
    card.requirementsHeader = requirementsHeader
    
    -- Create expandable content
    local expandedContent = self:CreateExpandableContent(card, requirementsHeader)
    
    -- Set up expand/collapse handler
    self:SetupAchievementExpandHandler(card, plan)
    
    -- CRITICAL: Restore expanded state if card was previously expanded
    -- This ensures UI matches the persisted state after window resize or layout recalculation
    if card.isExpanded then
        local achievementID = plan.achievementID
        if achievementID then
            local numCriteria = GetAchievementNumCriteria(achievementID)
            if numCriteria and numCriteria > 0 then
                -- ExpandAchievementContent already handles: expandedContent:Show(), requirementsHeader text, and card height
                PlanCardFactory:ExpandAchievementContent(card, achievementID)
            else
                -- ExpandAchievementEmpty already handles: expandedContent:Show(), requirementsHeader text, and card height
                PlanCardFactory:ExpandAchievementEmpty(card)
            end
            
            -- Update expand button icon (not handled by ExpandAchievementContent)
            if card._expandButton then
                self:UpdateExpandButtonIcon(card, true)
            end
        end
    else
        -- Ensure collapsed state is correct
        if card.expandedContent then
            card.expandedContent:Hide()
        end
        if card.requirementsHeader then
            card.requirementsHeader:SetText("|cffffcc00" .. NormalizeColonLabelSpacing((ns.L and ns.L["REQUIREMENTS_LABEL"]) or "Requirements:") .. "|r ...")
        end
        if card._expandButton then
            self:UpdateExpandButtonIcon(card, false)
        end
    end

    self:ReflowAchievementCard(card)
end

--[[
    Setup achievement expand/collapse handler
]]
function PlanCardFactory:SetupAchievementExpandHandler(card, plan)
    -- Create unified expand button (20x20, same size as delete button)
    local expandButton = self:CreateExpandButton(card, card.isExpanded or false)
    
    local factory = self
    
    -- Setup expand callback
    local expandCallback = function(cardFrame)
        local achievementID = cardFrame.planAchievementID or plan.achievementID
        if not achievementID then return end
        
        if cardFrame.isExpanded then
            -- Collapse
            cardFrame.isExpanded = false
            if cardFrame.cardKey then
                ns.expandedCards[cardFrame.cardKey] = false
            end
            if cardFrame.expandedContent then
                cardFrame.expandedContent:Hide()
            end
            if cardFrame.requirementsHeader then
                cardFrame.requirementsHeader:SetText("|cffffcc00" .. NormalizeColonLabelSpacing((ns.L and ns.L["REQUIREMENTS_LABEL"]) or "Requirements:") .. "|r ...")
            end
            
            -- Recalculate progress when collapsed to show same format as expanded
            if achievementID and cardFrame.progressLabel then
                local numCriteria = GetAchievementNumCriteria(achievementID)
                if numCriteria and numCriteria > 0 then
                    local completedCount = 0
                    local totalQuantity = 0
                    local totalReqQuantity = 0
                    local hasProgressBased = false
                    
                    for criteriaIndex = 1, numCriteria do
                        local criteriaName, criteriaType, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, criteriaIndex)
                        if criteriaName and criteriaName ~= "" then
                            if completed then
                                completedCount = completedCount + 1
                            end
                            if quantity and reqQuantity and reqQuantity > 0 then
                                totalQuantity = totalQuantity + (quantity or 0)
                                totalReqQuantity = totalReqQuantity + (reqQuantity or 0)
                                hasProgressBased = true
                            end
                        end
                    end
                    
            local P = ns.PLAN_UI_COLORS or {}
            local progressColor = (completedCount == numCriteria) and (P.progressFull or "|cff00ff00") or (P.incomplete or "|cffffffff")
            if hasProgressBased and totalReqQuantity > 0 then
                local progressFmt = (ns.L and ns.L["PROGRESS_ON_FORMAT"]) or "You are %d / %d on the progress"
                local progressText = (P.progressLabel or "|cffffcc00") .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r " .. progressColor .. string.format(progressFmt, totalQuantity, totalReqQuantity) .. "|r"
                        cardFrame.progressLabel:SetText(FormatTextNumbers(progressText))
                    else
                        -- Criteria-based: "You completed X of Y total requirements"
                        local reqFmt = (ns.L and ns.L["COMPLETED_REQ_FORMAT"]) or "You completed %d of %d total requirements"
                        local progressText = "|cffffcc00" .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r " .. progressColor .. string.format(reqFmt, completedCount, numCriteria) .. "|r"
                        cardFrame.progressLabel:SetText(FormatTextNumbers(progressText))
                    end
                else
                    cardFrame.progressLabel:SetText("|cffffcc00" .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r")
                end
            elseif cardFrame.progressLabel then
                cardFrame.progressLabel:SetText("|cffffcc00" .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r")
            end
            
            factory:ReflowAchievementCard(cardFrame)
            -- Update expand button icon
            factory:UpdateExpandButtonIcon(cardFrame, false)
        else
            -- Expand
            cardFrame.isExpanded = true
            if cardFrame.cardKey then
                ns.expandedCards[cardFrame.cardKey] = true
            end
            
            local numCriteria = GetAchievementNumCriteria(achievementID)
            if numCriteria and numCriteria > 0 then
                PlanCardFactory:ExpandAchievementContent(cardFrame, achievementID)
                if cardFrame.expandedContent then
                    cardFrame.expandedContent:Show()
                end
            else
                PlanCardFactory:ExpandAchievementEmpty(cardFrame)
            end
            
            -- Update requirements header text
            if cardFrame.requirementsHeader then
                cardFrame.requirementsHeader:SetText("|cffffcc00" .. NormalizeColonLabelSpacing((ns.L and ns.L["REQUIREMENTS_LABEL"]) or "Requirements:") .. "|r")
            end
            
            -- Update expand button icon
            factory:UpdateExpandButtonIcon(cardFrame, true)
        end
    end
    
    -- Setup card click handler
    self:SetupCardClickHandler(card, expandCallback)
    
    -- Also setup expand button click
    expandButton:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        expandCallback(card)
    end)
end

--[[
    Expand achievement content with criteria
]]
function PlanCardFactory:ExpandAchievementContent(card, achievementID)
    local expandedContent = card.expandedContent
    if not expandedContent then 
        return 
    end
    
    -- CRITICAL: Re-anchor expandedContent to requirementsHeader to ensure correct positioning
    local anchorFrame = card.requirementsHeader
    if anchorFrame then
        -- Clear all points and re-anchor to ensure correct position
        expandedContent:ClearAllPoints()
        expandedContent:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -8)
        expandedContent:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
    end
    
    -- Clear previous content
    local bin = ns.UI_RecycleBin
    for i = expandedContent:GetNumChildren(), 1, -1 do
        local child = select(i, expandedContent:GetChildren())
        if child then
            child:Hide()
            if bin then child:SetParent(bin) else child:SetParent(nil) end
        end
    end
    
    local completedCount = 0
    local criteriaDetails = {}
    local totalQuantity = 0
    local totalReqQuantity = 0
    local hasProgressBased = false
    
    local CRITERIA_TYPE_ACHIEVEMENT = 8
    for criteriaIndex = 1, GetAchievementNumCriteria(achievementID) do
        local criteriaName, criteriaType, completed, quantity, reqQuantity, charName, flags, assetID = GetAchievementCriteriaInfo(achievementID, criteriaIndex)
        if criteriaName and criteriaName ~= "" then
            if completed then
                completedCount = completedCount + 1
            end
            
            local progressText = ""
            if quantity and reqQuantity and reqQuantity > 0 then
                totalQuantity = totalQuantity + (quantity or 0)
                totalReqQuantity = totalReqQuantity + (reqQuantity or 0)
                hasProgressBased = true
                -- Only show (x/y) on line when reqQuantity > 1; skip 0/1 and 1/1 for kill objectives
                if reqQuantity > 1 then
                    progressText = string.format(" |cffffffff(%s / %s)|r", FormatNumber(quantity), FormatNumber(reqQuantity))
                end
            end
            
            -- Detect achievement-type criteria (criteriaType 8 = another achievement)
            local linkedAchievementID = nil
            if criteriaType == CRITERIA_TYPE_ACHIEVEMENT and assetID and assetID > 0 then
                linkedAchievementID = assetID
            end
            
            -- Light blue for achievement-linked criteria, green/white for others
            local textColor
            if linkedAchievementID then
                textColor = completed and "|cff44ddff" or "|cff44bbff"
            else
                local P3 = ns.PLAN_UI_COLORS or {}
                textColor = completed and (P3.completed or "|cff44ff44") or (P3.incomplete or "|cffffffff")
            end
            
            local formattedCriteriaName = FormatTextNumbers(criteriaName)
            -- Append (Planned) for linked achievements that are in plans
            local plannedSuffix = ""
            if linkedAchievementID then
                local WarbandNexus = ns.WarbandNexus
                if WarbandNexus and WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(linkedAchievementID) then
                    local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
                    plannedSuffix = " |cffffcc00(" .. plannedWord .. ")|r"
                end
            end
            table.insert(criteriaDetails, {
                completed = completed,
                text = textColor .. formattedCriteriaName .. "|r" .. progressText .. plannedSuffix,
                linkedAchievementID = linkedAchievementID,
            })
        end
    end
    
    -- Update progress label with appropriate text based on achievement type
    local numCriteria = #criteriaDetails
    local P4 = ns.PLAN_UI_COLORS or {}
    local progressColor = (completedCount == numCriteria) and (P4.progressFull or "|cff00ff00") or (P4.incomplete or "|cffffffff")
    if card.progressLabel then
        if hasProgressBased and totalReqQuantity > 0 then
            local progressFmt = (ns.L and ns.L["PROGRESS_ON_FORMAT"]) or "You are %d / %d on the progress"
            local progressText = (P4.progressLabel or "|cffffcc00") .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r " .. progressColor .. string.format(progressFmt, totalQuantity, totalReqQuantity) .. "|r"
            card.progressLabel:SetText(FormatTextNumbers(progressText))
        else
            local reqFmt = (ns.L and ns.L["COMPLETED_REQ_FORMAT"]) or "You completed %d of %d total requirements"
            local progressText = (P4.progressLabel or "|cffffcc00") .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r " .. progressColor .. string.format(reqFmt, completedCount, numCriteria) .. "|r"
            card.progressLabel:SetText(FormatTextNumbers(progressText))
        end
    end
    
    -- Information text is now updated in card.infoText directly (not in expandedContent)
    -- This ensures it's shown/hidden correctly on expand/collapse
    local contentY = 0
    
    -- Criteria grid: max 2 columns when wide, 1 column when narrow
    local availableWidth = expandedContent:GetWidth()
    if availableWidth <= 0 then
        availableWidth = (card:GetWidth() or 200) - 40
    end
    local criteriaY = contentY - 8
    local numCols = (availableWidth >= 360) and 2 or 1
    local colWidth = availableWidth / numCols
    local ICON_COL_WIDTH = 18
    local currentRow = {}
    
    local ShowAchievementPopup = ns.UI_ShowAchievementPopup
    
    for i, criteriaData in ipairs(criteriaDetails) do
        table.insert(currentRow, criteriaData)
        
        if #currentRow == numCols or i == #criteriaDetails then
            for colIdx, data in ipairs(currentRow) do
                local xPos = (colIdx - 1) * colWidth
                local linkedID = data.linkedAchievementID
                
                -- Icon column (fixed width for consistent alignment)
                local iconLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                iconLabel:SetPoint("TOPLEFT", xPos, criteriaY)
                iconLabel:SetWidth(ICON_COL_WIDTH)
                iconLabel:SetJustifyH("CENTER")
                if data.completed then
                    iconLabel:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t")
                else
                    iconLabel:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t")
                end
                
                if linkedID and ShowAchievementPopup and not data.completed then
                    -- Interactive: Button frame for incomplete achievement-linked criteria
                    local btn = CreateFrame("Button", nil, expandedContent)
                    btn:SetPoint("TOPLEFT", xPos + ICON_COL_WIDTH, criteriaY)
                    btn:SetSize(colWidth - ICON_COL_WIDTH - 4, 16)
                    
                    local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
                    label:SetPoint("LEFT")
                    label:SetWidth(colWidth - ICON_COL_WIDTH - 8)
                    label:SetJustifyH("LEFT")
                    label:SetText(data.text)
                    label:SetWordWrap(false)
                    label:SetMaxLines(1)
                    
                    btn:SetScript("OnEnter", function()
                        label:SetAlpha(0.7)
                    end)
                    btn:SetScript("OnLeave", function()
                        label:SetAlpha(1)
                    end)
                    btn:SetScript("OnClick", function(self)
                        ShowAchievementPopup(linkedID, self)
                    end)
                else
                    -- Standard: plain FontString for non-achievement criteria
                    local colLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    colLabel:SetPoint("TOPLEFT", xPos + ICON_COL_WIDTH, criteriaY)
                    colLabel:SetWidth(colWidth - ICON_COL_WIDTH - 4)
                    colLabel:SetJustifyH("LEFT")
                    colLabel:SetText(data.text)
                    colLabel:SetWordWrap(false)
                    colLabel:SetNonSpaceWrap(false)
                    colLabel:SetMaxLines(1)
                end
            end
            criteriaY = criteriaY - 16
            currentRow = {}
        end
    end
    
    local ecPadding = 10
    expandedContent:SetHeight(math.max(ecPadding, math.abs(criteriaY) + ecPadding))
    expandedContent:Show()
    if card.requirementsHeader then
        card.requirementsHeader:SetText("|cffffcc00" .. NormalizeColonLabelSpacing((ns.L and ns.L["REQUIREMENTS_LABEL"]) or "Requirements:") .. "|r")
        card.requirementsHeader:Show()
    end

    PlanCardFactory:ReflowAchievementCard(card)
end

--[[
    Expand achievement with no criteria — Criteria yoksa hiçbir yerde gösterme (header + bölüm gizli)
]]
function PlanCardFactory:ExpandAchievementEmpty(card)
    local expandedContent = card.expandedContent
    if not expandedContent then return end

    local bin = ns.UI_RecycleBin
    for i = expandedContent:GetNumChildren(), 1, -1 do
        local child = select(i, expandedContent:GetChildren())
        if child then
            child:Hide()
            if bin then child:SetParent(bin) else child:SetParent(nil) end
        end
    end

    if card.requirementsHeader then
        card.requirementsHeader:Hide()
    end
    expandedContent:Hide()
    PlanCardFactory:ReflowAchievementCard(card)
end

--[[
    Create mount card
]]
function PlanCardFactory:CreateMountCard(card, plan, progress, nameText)
    if not card or not plan then
        return
    end
    
    -- Create type badge
    if nameText then
        self:CreateTypeBadge(card, plan, nameText)
    end
    
    -- Create source info (always creates something, even if source is missing)
    local lastTextElement = self:CreateSourceInfo(card, plan, -60)
    
    -- Setup expand handler for multiple sources (without Details label)
    if lastTextElement then
        self:SetupSourceExpandHandler(card, plan, "mount", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupSourceExpandHandler(card, plan, "mount", anchorFrame)
    end
    
    if card._isSourceExpanded and card._sourceExpandButton then
        self:CreateSourceInfo(card, plan, -60)
        if card._sourceExpandButton then
            self:UpdateExpandButtonIcon(card, true)
        end
    end
    self:ReflowSourcePlanCard(card)
end

--[[
    Create pet card
]]
function PlanCardFactory:CreatePetCard(card, plan, progress, nameText)
    if not card or not plan then
        return
    end
    
    if nameText then
        self:CreateTypeBadge(card, plan, nameText)
    end
    
    local lastTextElement = self:CreateSourceInfo(card, plan, -60)
    if lastTextElement then
        self:SetupSourceExpandHandler(card, plan, "pet", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupSourceExpandHandler(card, plan, "pet", anchorFrame)
    end
    
    if card._isSourceExpanded and card._sourceExpandButton then
        self:CreateSourceInfo(card, plan, -60)
        if card._sourceExpandButton then
            self:UpdateExpandButtonIcon(card, true)
        end
    end
    self:ReflowSourcePlanCard(card)
end

--[[
    Create toy card
]]
function PlanCardFactory:CreateToyCard(card, plan, progress, nameText)
    if not card or not plan then
        return
    end
    
    if nameText then
        self:CreateTypeBadge(card, plan, nameText)
    end
    
    local lastTextElement = self:CreateSourceInfo(card, plan, -60)
    if lastTextElement then
        self:SetupSourceExpandHandler(card, plan, "toy", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupSourceExpandHandler(card, plan, "toy", anchorFrame)
    end
    
    if card._isSourceExpanded and card._sourceExpandButton then
        self:CreateSourceInfo(card, plan, -60)
        if card._sourceExpandButton then
            self:UpdateExpandButtonIcon(card, true)
        end
    end
    self:ReflowSourcePlanCard(card)
end

--[[
    Create illusion card
]]
function PlanCardFactory:CreateIllusionCard(card, plan, progress, nameText)
    if not card or not plan then
        return
    end
    
    if nameText then
        self:CreateTypeBadge(card, plan, nameText)
    end
    
    local lastTextElement = self:CreateSourceInfo(card, plan, -60)
    if lastTextElement then
        self:SetupSourceExpandHandler(card, plan, "illusion", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupSourceExpandHandler(card, plan, "illusion", anchorFrame)
    end
    
    if card._isSourceExpanded and card._sourceExpandButton then
        self:CreateSourceInfo(card, plan, -60)
        if card._sourceExpandButton then
            self:UpdateExpandButtonIcon(card, true)
        end
    end
    self:ReflowSourcePlanCard(card)
end

--[[
    Create title card
]]
function PlanCardFactory:CreateTitleCard(card, plan, progress, nameText)
    if not card or not plan then
        return
    end
    
    if nameText then
        self:CreateTypeBadge(card, plan, nameText)
    end
    
    local lastTextElement = self:CreateSourceInfo(card, plan, -60)
    if lastTextElement then
        self:SetupSourceExpandHandler(card, plan, "title", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupSourceExpandHandler(card, plan, "title", anchorFrame)
    end
    
    if card._isSourceExpanded and card._sourceExpandButton then
        self:CreateSourceInfo(card, plan, -60)
        if card._sourceExpandButton then
            self:UpdateExpandButtonIcon(card, true)
        end
    end
    self:ReflowSourcePlanCard(card)
end

--[[
    Create default card for other types
]]
function PlanCardFactory:CreateDefaultCard(card, plan, progress, nameText)
    -- Custom cards: Only show type badge and description (no source info)
    if plan.type == "custom" then
        if nameText then
            self:CreateTypeBadge(card, plan, nameText)
        end
        
        -- Reset timer + cycle indicator for custom plans with reset cycle
        if plan.resetCycle and plan.resetCycle.enabled then
            local isCompleted = progress and progress.collected
            local CreateResetTimer = ns.UI_CreateResetTimer
            if CreateResetTimer then
                if isCompleted then
                    -- Completed layout: [Timer] [Delete X] — delete at top-right, timer to its left
                    local removeBtn = ns.UI.Factory:CreateButton(card, 20, 20, true)
                    removeBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
                    removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
                    removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
                    removeBtn:SetScript("OnClick", function()
                        WarbandNexus:RemovePlan(plan.id)
                    end)
                    removeBtn:SetScript("OnEnter", function(self)
                        ns.TooltipService:Show(
                            self,
                            {
                                type = "custom",
                                title = (ns.L and ns.L["PLAN_ACTION_DELETE"]) or "Delete the Plan",
                                icon = false,
                                anchor = "ANCHOR_TOP",
                                lines = {}
                            }
                        )
                    end)
                    removeBtn:SetScript("OnLeave", function() ns.TooltipService:Hide() end)
                    
                    -- Timer anchored to the left of delete button
                    local resetTimer = CreateResetTimer(card, "TOPRIGHT", -32, -10, function()
                        if plan.resetCycle.resetType == "weekly" then
                            return WarbandNexus:GetWeeklyResetTime() - GetServerTime()
                        else
                            return C_DateAndTime.GetSecondsUntilDailyReset()
                        end
                    end)
                    card.resetTimer = resetTimer
                    
                    -- Cycle progress below timer
                    if plan.resetCycle.totalCycles and plan.resetCycle.totalCycles > 0 then
                        local remaining = plan.resetCycle.remainingCycles or 0
                        local total = plan.resetCycle.totalCycles
                        local elapsed = total - remaining
                        local unitText = plan.resetCycle.resetType == "daily"
                            and ((ns.L and ns.L["DAYS_LABEL"]) or "days")
                            or ((ns.L and ns.L["WEEKS_LABEL"]) or "weeks")
                        local cycleText = FontManager:CreateFontString(card, "small", "OVERLAY")
                        cycleText:SetPoint("TOPRIGHT", resetTimer.container, "BOTTOMRIGHT", 0, -2)
                        cycleText:SetText(string.format("|cffaaaaaa%d / %d %s|r", elapsed, total, unitText))
                        cycleText:SetJustifyH("RIGHT")
                        card.cycleText = cycleText
                    end
                else
                    -- Active layout: timer offset left for complete + delete buttons
                    local resetTimer = CreateResetTimer(card, "TOPRIGHT", -60, -10, function()
                        if plan.resetCycle.resetType == "weekly" then
                            return WarbandNexus:GetWeeklyResetTime() - GetServerTime()
                        else
                            return C_DateAndTime.GetSecondsUntilDailyReset()
                        end
                    end)
                    card.resetTimer = resetTimer
                    
                    -- Cycle progress below timer
                    if plan.resetCycle.totalCycles and plan.resetCycle.totalCycles > 0 then
                        local remaining = plan.resetCycle.remainingCycles or 0
                        local total = plan.resetCycle.totalCycles
                        local elapsed = total - remaining
                        local unitText = plan.resetCycle.resetType == "daily"
                            and ((ns.L and ns.L["DAYS_LABEL"]) or "days")
                            or ((ns.L and ns.L["WEEKS_LABEL"]) or "weeks")
                        local cycleText = FontManager:CreateFontString(card, "small", "OVERLAY")
                        cycleText:SetPoint("TOPRIGHT", resetTimer.container, "BOTTOMRIGHT", 0, -2)
                        cycleText:SetText(string.format("|cffaaaaaa%d / %d %s|r", elapsed, total, unitText))
                        cycleText:SetJustifyH("RIGHT")
                        card.cycleText = cycleText
                    end
                end
            end
        end
        
        -- Show description text (user-entered text) below type badge with expand/collapse
        -- Use same container approach as non-achievement cards
        self:CreateCustomDescription(card, plan, -60)
        
        -- CRITICAL: Restore expanded state if card was previously expanded
        if card._isDescriptionExpanded and card.descriptionText and card.fullDescription then
            -- Update description text to full version
            card.descriptionText:SetText("|cff88ff88" .. NormalizeColonLabelSpacing((ns.L and ns.L["DESCRIPTION_LABEL"]) or "Description:") .. "|r |cffffffff" .. FormatTextNumbers(card.fullDescription) .. "|r")
            card.descriptionText:SetWordWrap(true)  -- Allow wrapping
            card.descriptionText:SetMaxLines(0)  -- No limit when expanded
            
            -- Update expand button icon
            if card._expandButton then
                self:UpdateExpandButtonIcon(card, true)
            end
            
            -- Calculate and set expanded height
            local originalHeight = card.originalHeight or 130
            local textHeight = card.descriptionText:GetStringHeight()
            
            -- If height is too small (text not rendered yet), use estimation
            if textHeight < 14 then
                local cardWidth = card:GetWidth() or 200
                local availableWidth = cardWidth - 40
                local charsPerLine = math.floor(availableWidth / 6)
                local estimatedLines = math.max(1, math.ceil(string.len(card.fullDescription) / charsPerLine))
                textHeight = estimatedLines * 14
            end
            
            local collapsedHeight = 14  -- Single line height (14px)
            local expandedHeight = originalHeight + (textHeight - collapsedHeight)
            card:SetHeight(expandedHeight)
            
            -- Update layout
            if CardLayoutManager and card._layoutManager then
                CardLayoutManager:UpdateCardHeight(card, expandedHeight)
            end
        end
    else
        -- Other default cards: show type badge and source info
        self:CreateTypeBadge(card, plan, nameText)
        self:CreateSourceInfo(card, plan, -60)
        self:ReflowSourcePlanCard(card)
    end
end

--[[
    Create custom description with expand/collapse (EXACTLY like achievement Information field)
    @param card Frame - Card frame
    @param plan table - Plan data
    @param descY number - Y offset for description
]]
function PlanCardFactory:CreateCustomDescription(card, plan, descY)
    local description = plan.source or plan.description or plan.note or ""
    local customPlanDefault = (ns.L and ns.L["CUSTOM_PLAN_SOURCE"]) or "Custom plan"
    if not description or description == "" or description == "Custom plan" or description == customPlanDefault then
        return
    end
    
    -- Store full description
    card.fullDescription = description
    
    -- Initialize expand state (restore from persistent storage)
    if not card.cardKey then
        card.cardKey = "plan_" .. (plan.id or "unknown")
    end
    if not ns.expandedCards then
        ns.expandedCards = {}
    end
    local descExpandKey = card.cardKey .. "_description"
    if card._isDescriptionExpanded == nil then
        card._isDescriptionExpanded = ns.expandedCards[descExpandKey] or false
    end
    if type(card._isDescriptionExpanded) ~= "boolean" then
        card._isDescriptionExpanded = false
    end
    
    -- Destroy old description elements if exist
    local bin = ns.UI_RecycleBin
    if card.descriptionText then
        card.descriptionText:Hide()
        if bin then card.descriptionText:SetParent(bin) else card.descriptionText:SetParent(nil) end
        card.descriptionText = nil
    end
    if card.descriptionTextRest then
        card.descriptionTextRest:Hide()
        if bin then card.descriptionTextRest:SetParent(bin) else card.descriptionTextRest:SetParent(nil) end
        card.descriptionTextRest = nil
    end
    if card.descriptionLabel then
        card.descriptionLabel:Hide()
        if bin then card.descriptionLabel:SetParent(bin) else card.descriptionLabel:SetParent(nil) end
        card.descriptionLabel = nil
    end
    
    -- Calculate truncated description
    local cardWidth = card:GetWidth() or 200
    local availableWidth = cardWidth - 110  -- 10px left + label width (~85px) + 15px spacing
    local charsPerLine = math.floor(availableWidth / 6)  -- ~6 pixels per char
    local maxChars = charsPerLine * 2  -- 2 lines max for collapsed view
    maxChars = math.min(maxChars, 80)  -- Cap at 80 chars for safety
    
    local truncatedDescription = description
    if #description > maxChars then
        truncatedDescription = description:sub(1, maxChars - 3) .. "..."
    end
    
    -- Check if description needs expand
    local needsExpand = string.len(description) > maxChars
    card._needsDescriptionExpand = needsExpand
    
    -- Create label
    local descLabel = FontManager:CreateFontString(card, "body", "OVERLAY")
    descLabel:SetPoint("TOPLEFT", 10, descY)
    descLabel:SetText("|cff88ff88" .. NormalizeColonLabelSpacing((ns.L and ns.L["DESCRIPTION_LABEL"]) or "Description:") .. "|r")
    card.descriptionLabel = descLabel
    
    local labelWidth = descLabel:GetStringWidth()
    
    if not card._isDescriptionExpanded then
        -- Collapsed: First line text only
        local descText = FontManager:CreateFontString(card, "body", "OVERLAY")
        descText:SetPoint("LEFT", descLabel, "RIGHT", 5, 0)
        descText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(false)
        descText:SetNonSpaceWrap(false)  -- Prevent long word overflow
        descText:SetMaxLines(1)
        descText:SetText(FormatTextNumbers(truncatedDescription))
        card.descriptionText = descText
    else
        -- Expanded: Manual text breaking for multi-line
        -- Calculate how many chars fit in first line (after label)
        local cardWidth = card:GetWidth() or 200
        local firstLineWidth = cardWidth - (10 + labelWidth + 5 + 30)  -- left + label + spacing + right
        local subsequentLineWidth = cardWidth - 40  -- 10px left + 30px right
        
        local charsPerFirstLine = math.floor(firstLineWidth / 6)
        local charsPerSubsequentLine = math.floor(subsequentLineWidth / 6)
        
        -- Store for potential use
        card._charsPerFirstLine = charsPerFirstLine
        card._charsPerSubsequentLine = charsPerSubsequentLine
        
        -- Break text into lines
        local firstLineText = description:sub(1, math.min(charsPerFirstLine, #description))
        local remainingText = #description > charsPerFirstLine and description:sub(charsPerFirstLine + 1) or ""
        
        -- First line (after label)
        local firstLineFS = FontManager:CreateFontString(card, "body", "OVERLAY")
        firstLineFS:SetPoint("LEFT", descLabel, "RIGHT", 5, 0)
        firstLineFS:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        firstLineFS:SetJustifyH("LEFT")
        firstLineFS:SetWordWrap(false)
        firstLineFS:SetNonSpaceWrap(false)  -- Prevent long word overflow
        firstLineFS:SetMaxLines(1)
        firstLineFS:SetText(firstLineText)
        card.descriptionText = firstLineFS
        
        -- Subsequent lines (below label start)
        if #remainingText > 0 then
            local restText = FontManager:CreateFontString(card, "body", "OVERLAY")
            restText:SetPoint("TOPLEFT", 10, descY - 14)
            restText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
            restText:SetJustifyH("LEFT")
            restText:SetJustifyV("TOP")
            restText:SetWordWrap(true)
            restText:SetNonSpaceWrap(false)  -- Changed: Don't break long words awkwardly
            restText:SetMaxLines(5)  -- Max 5 lines for expanded description
            restText:SetText(remainingText)
            card.descriptionTextRest = restText
        end
    end
    
    -- Setup expand handler if needed
    if needsExpand and not card._descriptionExpandHandlerSetup then
        card._descriptionExpandHandlerSetup = true
        self:SetupDescriptionExpandHandler(card, plan)
    end
end

--[[
    Setup description expand handler for custom cards (similar to SetupSourceExpandHandler)
]]
function PlanCardFactory:SetupDescriptionExpandHandler(card, plan)
    -- Create expand button
    local expandButton = self:CreateExpandButton(card, card._isDescriptionExpanded or false)
    card._expandButton = expandButton
    card._sourceExpandButton = expandButton
    
    local factory = self
    local expandCallback = function(cardFrame)
        -- Toggle expansion state
        local wasExpanded = cardFrame._isDescriptionExpanded or false
        cardFrame._isDescriptionExpanded = not wasExpanded
        
        -- Save state to persistent storage
        if cardFrame.cardKey then
            local descExpandKey = cardFrame.cardKey .. "_description"
            if not ns.expandedCards then
                ns.expandedCards = {}
            end
            ns.expandedCards[descExpandKey] = cardFrame._isDescriptionExpanded
        end
        
        -- Ensure state is boolean
        if type(cardFrame._isDescriptionExpanded) ~= "boolean" then
            cardFrame._isDescriptionExpanded = false
        end
        
        -- Update description text
        if cardFrame.fullDescription then
            -- Clear old elements
            local bin = ns.UI_RecycleBin
            if cardFrame.descriptionText then
                cardFrame.descriptionText:Hide()
                if bin then cardFrame.descriptionText:SetParent(bin) else cardFrame.descriptionText:SetParent(nil) end
                cardFrame.descriptionText = nil
            end
            if cardFrame.descriptionTextRest then
                cardFrame.descriptionTextRest:Hide()
                if bin then cardFrame.descriptionTextRest:SetParent(bin) else cardFrame.descriptionTextRest:SetParent(nil) end
                cardFrame.descriptionTextRest = nil
            end
            if cardFrame.descriptionLabel then
                cardFrame.descriptionLabel:Hide()
                if bin then cardFrame.descriptionLabel:SetParent(bin) else cardFrame.descriptionLabel:SetParent(nil) end
                cardFrame.descriptionLabel = nil
            end
            
            -- Calculate truncated description
            local cardWidth = cardFrame:GetWidth() or 200
            local collapsedAvailableWidth = cardWidth - 110
            local expandedAvailableWidth = cardWidth - 40
            local charsPerLineCollapsed = math.floor(collapsedAvailableWidth / 6)
            local charsPerLineExpanded = math.floor(expandedAvailableWidth / 6)
            local maxChars = math.min(charsPerLineCollapsed * 2, 80)
            
            local truncatedDescription = cardFrame.fullDescription
            if #cardFrame.fullDescription > maxChars then
                truncatedDescription = cardFrame.fullDescription:sub(1, maxChars - 3) .. "..."
            end
            
            local descY = -60
            
            -- Create label
            local descLabel = FontManager:CreateFontString(cardFrame, "body", "OVERLAY")
            descLabel:SetPoint("TOPLEFT", 10, descY)
            descLabel:SetText("|cff88ff88" .. NormalizeColonLabelSpacing((ns.L and ns.L["DESCRIPTION_LABEL"]) or "Description:") .. "|r")
            cardFrame.descriptionLabel = descLabel
            
            local labelWidth = descLabel:GetStringWidth()
            
            if not cardFrame._isDescriptionExpanded then
                -- Collapsed: First line text only
                local descText = FontManager:CreateFontString(cardFrame, "body", "OVERLAY")
                descText:SetPoint("LEFT", descLabel, "RIGHT", 5, 0)
                descText:SetPoint("RIGHT", cardFrame, "RIGHT", -30, 0)
                descText:SetJustifyH("LEFT")
                descText:SetWordWrap(false)
                descText:SetMaxLines(1)
                descText:SetText(FormatTextNumbers(truncatedDescription))
                cardFrame.descriptionText = descText
            else
                -- Expanded: Manual text breaking
                local cardWidth = cardFrame:GetWidth() or 200
                local firstLineWidth = cardWidth - (10 + labelWidth + 5 + 30)
                local subsequentLineWidth = cardWidth - 40
                
                local charsPerFirstLine = math.floor(firstLineWidth / 6)
                local charsPerSubsequentLine = math.floor(subsequentLineWidth / 6)
                
                -- Store for height calculation
                cardFrame._charsPerFirstLine = charsPerFirstLine
                cardFrame._charsPerSubsequentLine = charsPerSubsequentLine
                
                -- Break text
                local firstLineText = cardFrame.fullDescription:sub(1, math.min(charsPerFirstLine, #cardFrame.fullDescription))
                local remainingText = #cardFrame.fullDescription > charsPerFirstLine and cardFrame.fullDescription:sub(charsPerFirstLine + 1) or ""
                
                -- First line
                local firstLineFS = FontManager:CreateFontString(cardFrame, "body", "OVERLAY")
                firstLineFS:SetPoint("LEFT", descLabel, "RIGHT", 5, 0)
                firstLineFS:SetPoint("RIGHT", cardFrame, "RIGHT", -30, 0)
                firstLineFS:SetJustifyH("LEFT")
                firstLineFS:SetWordWrap(false)
                firstLineFS:SetMaxLines(1)
                firstLineFS:SetText(firstLineText)
                cardFrame.descriptionText = firstLineFS
                
                -- Subsequent lines
                if #remainingText > 0 then
                    local restText = FontManager:CreateFontString(cardFrame, "body", "OVERLAY")
                    restText:SetPoint("TOPLEFT", 10, descY - 14)
                    restText:SetPoint("RIGHT", cardFrame, "RIGHT", -30, 0)
                    restText:SetJustifyH("LEFT")
                    restText:SetJustifyV("TOP")
                    restText:SetWordWrap(true)
                    restText:SetMaxLines(0)
                    restText:SetNonSpaceWrap(true)
                    restText:SetText(remainingText)
                    cardFrame.descriptionTextRest = restText
                end
            end
            
            -- Calculate new card height based on expansion state
            local originalHeight = cardFrame.originalHeight or 130
            local newHeight = originalHeight
            
            if cardFrame._isDescriptionExpanded then
                -- Wait for text to render, then calculate accurate height.
                -- Reuse a single hidden frame to avoid frame accumulation.
                local updateFrame = ns._planDescUpdateFrame
                if not updateFrame then
                    updateFrame = CreateFrame("Frame", nil, UIParent)
                    updateFrame:SetSize(1, 1)
                    updateFrame:Hide()
                    ns._planDescUpdateFrame = updateFrame
                end
                updateFrame._targetCard = cardFrame
                updateFrame._origHeight = originalHeight
                updateFrame._count = 0
                updateFrame:SetScript("OnUpdate", function(self, elapsed)
                    self._count = self._count + 1
                    if self._count >= 2 then
                        local cf = self._targetCard
                        local restTextHeight = 0
                        if cf and cf.descriptionTextRest then
                            restTextHeight = cf.descriptionTextRest:GetStringHeight()
                        end
                        local collapsedHeight = 14
                        local labelAndFirstLineHeight = 14
                        local calculatedHeight = (self._origHeight or 130) - collapsedHeight + labelAndFirstLineHeight + restTextHeight
                        if cf then
                            cf:SetHeight(calculatedHeight)
                            if CardLayoutManager and cf._layoutManager then
                                CardLayoutManager:UpdateCardHeight(cf, calculatedHeight)
                            end
                        end
                        self:SetScript("OnUpdate", nil)
                    end
                end)
                updateFrame:Show()
                
                -- Set estimated height immediately
                local remainingTextLen = math.max(0, string.len(cardFrame.fullDescription) - (cardFrame._charsPerFirstLine or 0))
                local estimatedRestLines = math.ceil(remainingTextLen / (cardFrame._charsPerSubsequentLine or 1))
                local estimatedRestHeight = estimatedRestLines * 14
                newHeight = originalHeight + estimatedRestHeight
            end
            
            -- Update card height
            cardFrame:SetHeight(newHeight)
            
            -- Update expand button icon
            factory:UpdateExpandButtonIcon(cardFrame, cardFrame._isDescriptionExpanded)
            
            -- Update layout
            if CardLayoutManager and cardFrame._layoutManager then
                CardLayoutManager:UpdateCardHeight(cardFrame, newHeight)
            end
        end
    end
    
    -- Setup card click handler
    self:SetupCardClickHandler(card, expandCallback)
    
    -- Setup expand button click
    expandButton:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        expandCallback(card)
    end)
    
    -- Prevent expand button click from triggering card click
    expandButton:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            card.clickedOnExpandButton = true
        end
    end)
end

--[[
    Setup source expand handler for mount/pet/toy/illusion/title cards
    Expands to show all sources (without Details label)
]]
function PlanCardFactory:SetupSourceExpandHandler(card, plan, planType, anchorFrame)
    if not card._sources or #card._sources == 0 then
        return
    end

    -- One structured source: full text wraps inside the card (dynamic height via ReflowSourcePlanCard).
    if #card._sources <= 1 then
        return
    end

    card._needsExpand = true
    
    -- Create unified expand button (20x20, same size as delete button)
    local expandButton = self:CreateExpandButton(card, card._isSourceExpanded or false)
    
    local factory = self
    -- Setup expand callback (mimicking achievement system exactly)
    local expandCallback = function(cardFrame)
        -- Toggle source expansion state FIRST
        local wasExpanded = cardFrame._isSourceExpanded or false
        cardFrame._isSourceExpanded = not wasExpanded
        
        -- CRITICAL: Save state to persistent storage (like achievement cards)
        if cardFrame.cardKey then
            local sourceExpandKey = cardFrame.cardKey .. "_source"
            if not ns.expandedCards then
                ns.expandedCards = {}
            end
            ns.expandedCards[sourceExpandKey] = cardFrame._isSourceExpanded
        end
        
        -- CRITICAL: Ensure _needsExpand is set if expand button exists
        if cardFrame._sourceExpandButton then
            cardFrame._needsExpand = true
        end
        
        -- CRITICAL: Ensure state is boolean, not nil
        if cardFrame._isSourceExpanded == nil then
            cardFrame._isSourceExpanded = false
        end
        
        if cardFrame._isSourceExpanded then
            factory:CreateSourceInfo(cardFrame, plan, -PLAN_CARD_CONTENT_TOP)
        else
            factory:CreateSourceInfo(cardFrame, plan, -PLAN_CARD_CONTENT_TOP)
        end
        
        factory:ReflowSourcePlanCard(cardFrame)
        factory:UpdateExpandButtonIcon(cardFrame, cardFrame._isSourceExpanded)
    end
    
    -- Setup card click handler
    self:SetupCardClickHandler(card, expandCallback)
    
    -- Also setup expand button click (prevent card click handler from firing)
    expandButton:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        -- Prevent event bubbling to card
        expandCallback(card)
    end)
    
    -- Prevent expand button click from triggering card click
    expandButton:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            -- Mark that click was on expand button to prevent card handler
            if card then
                card.clickedOnExpandButton = true
            end
        end
    end)
    
    card._sourceExpandButton = expandButton
end

--[[
    Setup generic expand handler for achievement cards only
    NOTE: This is now handled by SetupAchievementExpandHandler
    This function is kept for backward compatibility but does nothing
]]
function PlanCardFactory:SetupExpandHandler(card, plan, planType, anchorFrame)
    -- Only Achievement cards have expand functionality
    -- But this is now handled by SetupAchievementExpandHandler
    -- This function is kept for backward compatibility
    if planType ~= "achievement" then
        return
    end
end

--[[
    Expand card content based on type
]]
function PlanCardFactory:ExpandCardContent(card, planType)
    local expandedContent = card.expandedContent
    if not expandedContent then return end
    
    -- Clear previous content
    local bin = ns.UI_RecycleBin
    for i = expandedContent:GetNumChildren(), 1, -1 do
        local child = select(i, expandedContent:GetChildren())
        if child then
            child:Hide()
            if bin then child:SetParent(bin) else child:SetParent(nil) end
        end
    end
    
    local plan = card.plan
    local contentHeight = 0
    
    -- Type-specific expanded content
    -- Only Achievement cards have expand functionality
    if planType == "achievement" then
        -- Achievement expansion is handled in SetupAchievementExpandHandler
        -- This function is only called for achievement cards
        contentHeight = 0  -- Achievement has its own expansion logic
    elseif planType == "mount" then
        contentHeight = 0  -- No expand for mount
    elseif planType == "pet" then
        contentHeight = 0  -- No expand for pet
    elseif planType == "toy" then
        contentHeight = 0  -- No expand for toy
    elseif planType == "illusion" then
        contentHeight = 0  -- No expand for illusion
    elseif planType == "title" then
        contentHeight = 0  -- No expand for title
    end
    
    -- Update card height
    local expandedHeight = card.originalHeight + contentHeight + 8
    card:SetHeight(expandedHeight)
    expandedContent:Show()
    card.expandHeader:SetText("|cffffcc00" .. NormalizeColonLabelSpacing((ns.L and ns.L["DETAILS_LABEL"]) or "Details:") .. "|r")
    
    -- Update layout
    if CardLayoutManager and card._layoutManager then
        CardLayoutManager:UpdateCardHeight(card, expandedHeight)
    end
end

--[[
    Expand mount content - Show full source information with all details
]]
function PlanCardFactory:ExpandMountContent(expandedContent, plan)
    local yOffset = 0
    
    -- Parse multiple sources to get structured data (vendor, zone, cost, etc.)
    local planSourceSafe = plan.source and type(plan.source) == "string" and not (issecretvalue and issecretvalue(plan.source))
    if planSourceSafe and WarbandNexus and WarbandNexus.ParseMultipleSources then
        local success, sources = pcall(function()
            return WarbandNexus:ParseMultipleSources(plan.source)
        end)
        
        if success and sources and #sources > 0 then
            -- Show each source with full details
            for i, source in ipairs(sources) do
                -- Vendor or Drop
                if source.vendor then
                    local vendorText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    vendorText:SetPoint("TOPLEFT", 0, yOffset)
                    vendorText:SetPoint("RIGHT", 0, 0)
                    vendorText:SetText("|cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["VENDOR_LABEL"]) or "Vendor:") .. "|r |cffffffff" .. source.vendor .. "|r")
                    vendorText:SetJustifyH("LEFT")
                    vendorText:SetWordWrap(true)
                    vendorText:SetNonSpaceWrap(false)
                    yOffset = PlanSourceAdvanceY(yOffset, vendorText, false)
                elseif source.npc then
                    local npcColor = "ffffffff"
                    local sourceDB = ns.CollectibleSourceDB
                    if sourceDB and sourceDB.lockoutNpcNames and sourceDB.lockoutQuests then
                        local npcID = sourceDB.lockoutNpcNames[source.npc]
                        if npcID then
                            local questData = sourceDB.lockoutQuests[npcID]
                            if questData then
                                local questIDs = type(questData) == "table" and questData or { questData }
                                for qi = 1, #questIDs do
                                    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questIDs[qi]) then
                                        npcColor = "ff666666"
                                        break
                                    end
                                end
                            end
                        end
                    end
                    local dropText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    dropText:SetPoint("TOPLEFT", 0, yOffset)
                    dropText:SetPoint("RIGHT", 0, 0)
                    dropText:SetText(PlanSourceIconMarkup("loot") .. " |cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["DROP_LABEL"]) or "Drop:") .. "|r |c" .. npcColor .. " " .. source.npc .. "|r")
                    dropText:SetJustifyH("LEFT")
                    dropText:SetWordWrap(true)
                    dropText:SetNonSpaceWrap(false)
                    yOffset = PlanSourceAdvanceY(yOffset, dropText, true)
                elseif source.quest then
                    local P = ns.PLAN_UI_COLORS or {}
                    local questLabel = NormalizeColonLabelSpacing((ns.L and ns.L["QUEST_LABEL"]) or "Quest:")
                    local questText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    questText:SetPoint("TOPLEFT", 0, yOffset)
                    questText:SetPoint("RIGHT", 0, 0)
                    questText:SetText(PlanSourceIconMarkup("quest") .. " " .. (P.sourceLabel or "|cff99ccff") .. questLabel .. "|r" .. (P.body or "|cffffffff") .. source.quest .. "|r")
                    questText:SetJustifyH("LEFT")
                    questText:SetWordWrap(true)
                    questText:SetNonSpaceWrap(false)
                    yOffset = PlanSourceAdvanceY(yOffset, questText, true)
                end
                
                -- Location (Zone) — append difficulty label for mounts (consistent white; avoid duplication)
                if source.zone then
                    local zoneDiffLabel = ""
                    if plan and plan.type == "mount" and WarbandNexus and WarbandNexus.GetDropDifficulty then
                        local mountID = plan.mountID
                        if mountID then
                            local diff = WarbandNexus:GetDropDifficulty("mount", mountID)
                            local z = source.zone
                            local zSafe = z and type(z) == "string" and not (issecretvalue and issecretvalue(z))
                            local dSafe = diff and not (issecretvalue and issecretvalue(diff))
                            if dSafe and zSafe then
                                if not z:find("(" .. diff .. ")", 1, true) then
                                    local P = ns.PLAN_UI_COLORS or {}
                                    local bodyColor = P.body or "|cffffffff"
                                    zoneDiffLabel = " " .. bodyColor .. "(" .. diff .. ")|r"
                                end
                            end
                        end
                    end
                    local locationText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    locationText:SetPoint("TOPLEFT", 0, yOffset)
                    locationText:SetPoint("RIGHT", 0, 0)
                    locationText:SetText(PlanSourceIconMarkup("location") .. " |cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["LOCATION_LABEL"]) or "Location:") .. "|r |cffffffff" .. source.zone .. "|r" .. zoneDiffLabel)
                    locationText:SetJustifyH("LEFT")
                    locationText:SetWordWrap(true)
                    locationText:SetNonSpaceWrap(false)
                    yOffset = PlanSourceAdvanceY(yOffset, locationText, true)
                end
                
                -- Cost (if available)
                if source.cost then
                    local costText = source.cost
                    if type(costText) ~= "string" or (issecretvalue and issecretvalue(costText)) then
                        costText = nil
                    end
                    local currencyName = nil
                    
                    -- Try to identify currency from source text
                    if costText and plan.source and type(plan.source) == "string" and not (issecretvalue and issecretvalue(plan.source)) then
                        for textureID in plan.source:gmatch("|T(%d+)[:|]") do
                            local texID = tonumber(textureID)
                            if texID then
                                local textureMap = {
                                    [3743738] = 1767,   [3726260] = 1885,   [4638724] = 2003,
                                    [5453417] = 2803,   [5915096] = 3056,    [463446] = 515,
                                    [236396] = 241,     [1357486] = 1166,
                                }
                                local currencyID = textureMap[texID]
                                if currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                                    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                                    if info and info.name and not (issecretvalue and issecretvalue(info.name)) then
                                        currencyName = info.name
                                        break
                                    end
                                end
                            end
                        end
                    end
                    
                    if costText and costText:match("[Gg]old") then
                        currencyName = (ns.L and ns.L["GOLD_LABEL"]) or "Gold"
                    end
                    
                    if costText and currencyName and not (issecretvalue and issecretvalue(currencyName))
                        and currencyName ~= "Gold" then
                        costText = costText:gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", "")
                        costText = costText .. " (" .. currencyName .. ")"
                    end
                    
                    if costText then
                        local costLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                        costLabel:SetPoint("TOPLEFT", 0, yOffset)
                        costLabel:SetPoint("RIGHT", 0, 0)
                        costLabel:SetText(PlanSourceIconMarkup("class") .. " |cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["COST_LABEL"]) or "Cost:") .. "|r |cffffffff" .. costText .. "|r")
                        costLabel:SetJustifyH("LEFT")
                        costLabel:SetWordWrap(true)
                        costLabel:SetNonSpaceWrap(false)
                        yOffset = PlanSourceAdvanceY(yOffset, costLabel, true)
                    end
                end
                
                -- Faction (if available)
                if source.faction then
                    local factionText = PlanSourceIconMarkup("class") .. " |cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["FACTION_LABEL"]) or "Faction:") .. "|r |cffffffff" .. source.faction .. "|r"
                    if source.renown then
                        local repType = source.isFriendship and ((ns.L and ns.L["FRIENDSHIP_LABEL"]) or "Friendship") or ((ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown")
                        factionText = factionText .. " |cffffcc00(" .. repType .. " " .. source.renown .. ")|r"
                    end
                    local factionLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    factionLabel:SetPoint("TOPLEFT", 0, yOffset)
                    factionLabel:SetPoint("RIGHT", 0, 0)
                    factionLabel:SetText(factionText)
                    factionLabel:SetJustifyH("LEFT")
                    factionLabel:SetWordWrap(true)
                    factionLabel:SetNonSpaceWrap(false)
                    yOffset = PlanSourceAdvanceY(yOffset, factionLabel, true)
                end
                
                -- Add spacing between sources
                if i < #sources then
                    yOffset = yOffset - 4
                end
            end
        else
            -- Fallback: Show raw source text if parsing fails
            local cleanSource = plan.source
            if type(cleanSource) ~= "string" or (issecretvalue and issecretvalue(cleanSource)) then
                cleanSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
            elseif WarbandNexus.CleanSourceText then
                cleanSource = WarbandNexus:CleanSourceText(cleanSource)
                if type(cleanSource) ~= "string" or (issecretvalue and issecretvalue(cleanSource)) then
                    cleanSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
                end
            end
            local sourceText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
            sourceText:SetPoint("TOPLEFT", 0, yOffset)
            sourceText:SetPoint("RIGHT", 0, 0)
            sourceText:SetText("|cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:") .. "|r |cffffffff" .. cleanSource .. "|r")
            sourceText:SetJustifyH("LEFT")
            sourceText:SetWordWrap(true)
            -- Ensure text is rendered before measuring height (use GetStringHeight after SetText)
            local textHeight = sourceText:GetStringHeight() or 20
            yOffset = yOffset - textHeight - 8
        end
    elseif plan.source then
        -- No ParseMultipleSources available, show raw text
        local cleanSource = plan.source
        if type(cleanSource) ~= "string" or (issecretvalue and issecretvalue(cleanSource)) then
            cleanSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        elseif WarbandNexus.CleanSourceText then
            cleanSource = WarbandNexus:CleanSourceText(cleanSource)
            if type(cleanSource) ~= "string" or (issecretvalue and issecretvalue(cleanSource)) then
                cleanSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
            end
        end
        local sourceText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
        sourceText:SetPoint("TOPLEFT", 0, yOffset)
        sourceText:SetPoint("RIGHT", 0, 0)
        sourceText:SetText("|cff99ccff" .. NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:") .. "|r |cffffffff" .. cleanSource .. "|r")
        sourceText:SetJustifyH("LEFT")
        sourceText:SetWordWrap(true)
        -- Use timer to ensure text is rendered before measuring height
        local textHeight = sourceText:GetStringHeight() or 20
        if textHeight < 14 then
            C_Timer.After(0, function()
                local measuredHeight = sourceText:GetStringHeight() or 20
                if measuredHeight > textHeight then
                    textHeight = measuredHeight
                end
            end)
        end
        yOffset = yOffset - textHeight - 8
    end
    
    return math.abs(yOffset)
end

--[[
    Expand pet content
]]
function PlanCardFactory:ExpandPetContent(expandedContent, plan)
    return self:ExpandMountContent(expandedContent, plan)  -- Same structure for now
end

--[[
    Expand toy content
]]
function PlanCardFactory:ExpandToyContent(expandedContent, plan)
    return self:ExpandMountContent(expandedContent, plan)  -- Same structure for now
end

--[[
    Expand illusion content
]]
function PlanCardFactory:ExpandIllusionContent(expandedContent, plan)
    return self:ExpandMountContent(expandedContent, plan)  -- Same structure for now
end

--[[
    Expand title content
]]
function PlanCardFactory:ExpandTitleContent(expandedContent, plan)
    return self:ExpandMountContent(expandedContent, plan)  -- Same structure for now
end

--[[
    Create Weekly Vault card with 3 progress slots
]]
function PlanCardFactory:CreateWeeklyVaultCard(card, plan, progress, nameText)
    local COLORS = ns.UI_COLORS
    local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
    local CreateIcon = ns.UI_CreateIcon
    local FontManager = ns.FontManager
    
    -- Get character class color
    local classColor = {1, 1, 1}
    if plan.characterClass then
        local classColors = RAID_CLASS_COLORS[plan.characterClass]
        if classColors then
            classColor = {classColors.r, classColors.g, classColors.b}
        end
    end
    
    -- === HEADER WITH ICON ===
    local iconBorder = ns.UI.Factory:CreateContainer(card, 46, 46)
    iconBorder:SetPoint("TOPLEFT", 10, -10)
    
    local iconFrameObj = CreateIcon(card, "greatVault-whole-normal", 42, true, nil, false)
    iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
    iconFrameObj:Show()
    
    -- Title (accent color, title font - larger)
    local titleText = FontManager:CreateFontString(card, "title", "OVERLAY")
    titleText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
    if plan.fullyCompleted then
        titleText:SetTextColor(0.2, 1, 0.2)
        titleText:SetText((ns.L and ns.L["WEEKLY_VAULT_COMPLETE"]) or "Weekly Vault Card - Complete")
    else
        titleText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        titleText:SetText((ns.L and ns.L["WEEKLY_VAULT_CARD"]) or "Weekly Vault Card")
    end
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    
    -- Character name + Realm (single line, below title)
    local charText = FontManager:CreateFontString(card, "body", "OVERLAY")
    charText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    charText:SetTextColor(classColor[1], classColor[2], classColor[3])
    local characterDisplay = plan.characterName
    if plan.characterRealm and plan.characterRealm ~= "" then
        local rShown = (ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(plan.characterRealm)) or plan.characterRealm
        characterDisplay = characterDisplay .. " - " .. rShown
    end
    charText:SetText(characterDisplay)
    
    -- Reset timer (standardized widget)
    local CreateResetTimer = ns.UI_CreateResetTimer
    local resetTimer = CreateResetTimer(
        card,
        "TOPRIGHT",
        -35,  -- 35px from right edge (space for delete button)
        -10,  -- 10px from top
        function()
            local resetTimestamp = WarbandNexus:GetWeeklyResetTime()
            return resetTimestamp - GetServerTime()
        end
    )
    card.resetTimer = resetTimer  -- Store for reference
    
    -- Delete button (using Factory pattern)
    local removeBtn = ns.UI.Factory:CreateButton(card, 20, 20, true)  -- noBorder=true
    removeBtn:SetPoint("TOPRIGHT", -8, -8)
    removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    removeBtn:SetScript("OnClick", function()
        WarbandNexus:RemovePlan(plan.id)
    end)
    
    -- Alert button
    local hasReminder = WarbandNexus.HasPlanReminder and WarbandNexus:HasPlanReminder(plan.id)
    local hasActiveReminder = WarbandNexus.HasActiveReminder and WarbandNexus:HasActiveReminder(plan.id)
    local alertBtn = ns.UI.Factory:CreateButton(card, 20, 20, true)
    alertBtn:SetPoint("TOPRIGHT", -60, -8)
    local bellTex = alertBtn:CreateTexture(nil, "ARTWORK")
    bellTex:SetSize(18, 18)
    bellTex:SetPoint("CENTER")
    bellTex:SetAtlas("minimap-genericevent-hornicon-small", true)
    if hasActiveReminder then
        bellTex:SetVertexColor(1, 0.6, 0)
    elseif hasReminder then
        bellTex:SetVertexColor(1, 0.82, 0)
    else
        bellTex:SetVertexColor(0.5, 0.5, 0.5)
    end
    alertBtn._bellTex = bellTex

    if hasActiveReminder then
        local pulseAG = alertBtn:CreateAnimationGroup()
        pulseAG:SetLooping("BOUNCE")
        local pulseAnim = pulseAG:CreateAnimation("Alpha")
        pulseAnim:SetFromAlpha(1)
        pulseAnim:SetToAlpha(0.3)
        pulseAnim:SetDuration(0.8)
        pulseAnim:SetSmoothing("IN_OUT")
        pulseAG:Play()
        alertBtn._pulseAG = pulseAG
    end

    alertBtn:SetScript("OnClick", function()
        if hasActiveReminder and WarbandNexus.DismissReminders then
            WarbandNexus:DismissReminders(plan.id)
            return
        end
        if WarbandNexus.ShowSetAlertDialog then
            WarbandNexus:ShowSetAlertDialog(plan.id)
        end
    end)
    alertBtn:SetScript("OnEnter", function(btn)
        if btn._bellTex then btn._bellTex:SetVertexColor(1, 0.9, 0.3) end
        if btn._pulseAG then btn._pulseAG:Stop(); btn:SetAlpha(1) end
        local tooltipTitle, tooltipLines
        local activeReminders = WarbandNexus.GetActiveReminders and WarbandNexus:GetActiveReminders(plan.id)
        if activeReminders then
            tooltipTitle = (ns.L and ns.L["REMINDER_PREFIX"]) or "Reminder"
            tooltipLines = {}
            for _, label in ipairs(activeReminders) do
                tooltipLines[#tooltipLines + 1] = { text = "|cffffd100" .. label .. "|r" }
            end
            tooltipLines[#tooltipLines + 1] = { text = " " }
            tooltipLines[#tooltipLines + 1] = { text = "|cff888888" .. ((ns.L and ns.L["CLICK_TO_DISMISS"]) or "Click to dismiss") .. "|r" }
        else
            tooltipTitle = hasReminder and ((ns.L and ns.L["ALERT_ACTIVE"]) or "Alert Active") or ((ns.L and ns.L["SET_ALERT"]) or "Set Alert")
            tooltipLines = {}
        end
        if ns.TooltipService then
            ns.TooltipService:Show(btn, { type = "custom", title = tooltipTitle, icon = false, anchor = "ANCHOR_TOP", lines = tooltipLines })
        end
    end)
    alertBtn:SetScript("OnLeave", function(btn)
        if btn._pulseAG then btn._pulseAG:Play() end
        if btn._bellTex then
            local activeNow = WarbandNexus.HasActiveReminder and WarbandNexus:HasActiveReminder(plan.id)
            local reminderSet = WarbandNexus.HasPlanReminder and WarbandNexus:HasPlanReminder(plan.id)
            if activeNow then
                btn._bellTex:SetVertexColor(1, 0.6, 0)
            elseif reminderSet then
                btn._bellTex:SetVertexColor(1, 0.82, 0)
            else
                btn._bellTex:SetVertexColor(0.5, 0.5, 0.5)
            end
        end
        if ns.TooltipService then ns.TooltipService:Hide() end
    end)
    
    -- === 3 PROGRESS SLOTS ===
    local currentProgress = WarbandNexus:GetWeeklyVaultProgress(plan.characterName, plan.characterRealm) or {
        dungeonCount = 0,
        raidBossCount = 0,
        worldActivityCount = 0
    }

    local vaultLootReady = false
    if WarbandNexus.HasUnclaimedVaultRewards then
        local ok, v = pcall(WarbandNexus.HasUnclaimedVaultRewards, WarbandNexus)
        vaultLootReady = ok and v == true
    end
    
    local contentY = -70
    local cardWidth = card:GetWidth()
    local availableWidth = cardWidth - 10 - 15
    local slotSpacing = 10
    local slotWidth = (availableWidth - slotSpacing * 2) / 3
    local slotHeight = 92
    
    local tracked = plan.trackedSlots or { dungeon = true, raid = true, world = true, specialAssignment = true }
    
    local saTotal = currentProgress.specialAssignmentTotal or (plan.progress and plan.progress.specialAssignmentTotal) or 2
    local saSlotData = plan.slots.specialAssignment or {
        {threshold = 1, completed = false, manualOverride = false},
        {threshold = 2, completed = false, manualOverride = false}
    }
    
    local allSlots = {
        {
            key = "dungeon",
            atlas = "questlog-questtypeicon-heroic",
            title = (ns.L and ns.L["VAULT_SLOT_DUNGEON"]) or "Dungeon",
            current = currentProgress.dungeonCount,
            max = 8,
            slotData = plan.slots.dungeon,
            thresholds = {1, 4, 8}
        },
        {
            key = "raid",
            atlas = "questlog-questtypeicon-raid",
            title = (ns.L and ns.L["VAULT_SLOT_RAIDS"]) or "Raids",
            current = currentProgress.raidBossCount,
            max = 6,
            slotData = plan.slots.raid,
            thresholds = {2, 4, 6}
        },
        {
            key = "world",
            atlas = "questlog-questtypeicon-Delves",
            title = (ns.L and ns.L["VAULT_SLOT_WORLD"]) or "World",
            current = currentProgress.worldActivityCount,
            max = 8,
            slotData = plan.slots.world,
            thresholds = {2, 4, 8}
        },
        {
            key = "specialAssignment",
            atlas = "questlog-questtypeicon-important",
            title = (ns.L and ns.L["VAULT_SLOT_SA"]) or "Assignments",
            current = currentProgress.specialAssignmentCount or 0,
            max = saTotal,
            slotData = saSlotData,
            thresholds = {1, saTotal}
        }
    }
    
    local slots = {}
    for _, s in ipairs(allSlots) do
        if tracked[s.key] then
            slots[#slots + 1] = s
        end
    end
    
    -- Recalculate slot width based on visible count
    local visibleCount = #slots
    if visibleCount > 0 then
        slotWidth = (availableWidth - slotSpacing * math.max(0, visibleCount - 1)) / visibleCount
    end
    
    for slotIndex, slot in ipairs(slots) do
        local slotX = 10 + (slotIndex - 1) * (slotWidth + slotSpacing)
        
        local slotFrame = ns.UI.Factory:CreateContainer(card, slotWidth, slotHeight)
        slotFrame:SetPoint("TOPLEFT", slotX, contentY)
        
        -- Title (centered above bar, no icon)
        local title = FontManager:CreateFontString(slotFrame, "title", "OVERLAY")
        title:SetPoint("TOP", slotFrame, "TOP", 0, -8)  -- Centered, moved up
        title:SetText(slot.title)
        title:SetTextColor(0.95, 0.95, 0.95)
        
        -- Progress Bar (closer to title)
        local barY = -32  -- Moved up from -52
        local barPadding = 18
        local barWidth = slotWidth - (barPadding * 2)
        local barHeight = 16
        
        local barBg = ns.UI.Factory:CreateContainer(slotFrame, barWidth, barHeight)
        barBg:SetPoint("TOP", slotFrame, "TOP", 0, barY)
        
        if ApplyVisuals then
            local accentBorderColor = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}
            ApplyVisuals(barBg, {0.05, 0.05, 0.07, 0.3}, accentBorderColor)
        end
        
        -- Progress Fill (capped at 100% to prevent overflow)
        local fillPercent = math.min(1.0, slot.current / slot.max)  -- Cap at 100%
        local innerBarWidth = barWidth - 2  -- Actual usable width inside border
        local fillWidth = innerBarWidth * fillPercent
        if fillWidth > 0 then
            local fill = barBg:CreateTexture(nil, "ARTWORK")
            fill:SetPoint("LEFT", barBg, "LEFT", 1, 0)
            fill:SetSize(fillWidth, barHeight - 2)
            fill:SetTexture("Interface\\Buttons\\WHITE8x8")
            fill:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        end
        
        -- Checkpoint Markers (positioned relative to inner bar width)
        local readyShort = (ns.L and ns.L["VAULT_LOOT_READY_SHORT"]) or "Ready!"
        for i, threshold in ipairs(slot.thresholds) do
            local checkpointSlot = slot.slotData[i]
            local slotProgress = math.min(slot.current, threshold)
            local completed = slot.current >= threshold
            
            local markerXPercent = threshold / slot.max
            local markerX = (markerXPercent * innerBarWidth) + 1  -- +1 for left border offset
            
            if vaultLootReady then
                local rl = FontManager:CreateFontString(slotFrame, "small", "OVERLAY")
                rl:SetPoint("TOP", barBg, "BOTTOMLEFT", markerX, -6)
                rl:SetWidth(math.max(32, innerBarWidth / math.max(1, #slot.thresholds) - 2))
                rl:SetJustifyH("CENTER")
                rl:SetText("|cff44ff44" .. readyShort .. "|r")
            else
                -- Checkpoint arrow
                local checkArrow = barBg:CreateTexture(nil, "OVERLAY")
                checkArrow:SetSize(24, 24)
                checkArrow:SetPoint("CENTER", barBg, "BOTTOMLEFT", markerX, 0)
                checkArrow:SetAtlas("MiniMap-QuestArrow")
                if completed then
                    checkArrow:SetVertexColor(0.2, 1, 0.2, 1)
                else
                    checkArrow:SetVertexColor(0.9, 0.9, 0.9, 1)
                end
                
                -- Checkpoint label (aligned with checkmark position)
                if completed then
                    local checkFrame = ns.UI.Factory:CreateContainer(slotFrame, 16, 16)
                    checkFrame:SetPoint("TOP", barBg, "BOTTOMLEFT", markerX, -10)
                    
                    local checkmark = checkFrame:CreateTexture(nil, "OVERLAY")
                    checkmark:SetAllPoints()
                    checkmark:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
                else
                    local label = FontManager:CreateFontString(slotFrame, "body", "OVERLAY")
                    label:SetPoint("TOP", barBg, "BOTTOMLEFT", markerX, -10)
                    label:SetTextColor(1, 1, 1)
                    local progressText = string.format("%d / %d", slotProgress, threshold)
                    label:SetText(FormatTextNumbers(progressText))
                end
            end
            
            -- Hidden checkbox for manual override
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
end

--[[
    Create Daily Quest card with category progress slots (mirrors vault card layout)
    @param card Frame - Parent card frame
    @param plan table - Daily quest plan data
]]
function PlanCardFactory:CreateDailyQuestCard(card, plan)
    local COLORS = ns.UI_COLORS
    local CreateIcon = ns.UI_CreateIcon
    local FontManager = ns.FontManager
    local ApplyVisuals = ns.UI_ApplyVisuals
    
    local classColor = {1, 1, 1}
    if plan.characterClass then
        local classColors = RAID_CLASS_COLORS[plan.characterClass]
        if classColors then
            classColor = {classColors.r, classColors.g, classColors.b}
        end
    end
    
    -- === HEADER WITH ICON ===
    local iconBorder = ns.UI.Factory:CreateContainer(card, 46, 46)
    iconBorder:SetPoint("TOPLEFT", 10, -10)
    
    local FALLBACK_ATLAS = "questlog-questtypeicon-daily"
    local iconTexture = plan.iconAtlas or plan.icon
    local iconIsAtlas = false
    
    if plan.iconAtlas then
        iconIsAtlas = true
    elseif plan.iconIsAtlas then
        iconIsAtlas = true
    elseif plan.icon and plan.icon ~= "" and ns.Utilities and ns.Utilities.IsAtlasName then
        local ok, result = pcall(ns.Utilities.IsAtlasName, ns.Utilities, plan.icon)
        iconIsAtlas = ok and result or false
    end
    
    if not iconTexture or iconTexture == "" then
        iconTexture = FALLBACK_ATLAS
        iconIsAtlas = true
    elseif not iconIsAtlas and plan.type == "daily_quests" then
        iconTexture = FALLBACK_ATLAS
        iconIsAtlas = true
    end
    
    local iconFrameObj = CreateIcon(card, iconTexture, 42, iconIsAtlas, nil, false)
    if iconFrameObj then
        iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
        iconFrameObj:Show()
    end
    
    local allComplete = true
    local totalAll, completedAll = 0, 0
    local categoryOrder = {"weeklyQuests", "worldQuests", "dailyQuests", "events"}
    for _, catKey in ipairs(categoryOrder) do
        if plan.questTypes and plan.questTypes[catKey] then
            for _, quest in ipairs(plan.quests and plan.quests[catKey] or {}) do
                if not quest.isSubQuest then
                    totalAll = totalAll + 1
                    if quest.isComplete then
                        completedAll = completedAll + 1
                    else
                        allComplete = false
                    end
                end
            end
        end
    end
    if totalAll == 0 then allComplete = false end
    
    local titleText = FontManager:CreateFontString(card, "header", "OVERLAY")
    titleText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
    if allComplete then
        titleText:SetTextColor(0.2, 1, 0.2)
        titleText:SetText(((ns.L and ns.L["DAILY_TASKS_PREFIX"]) or "Weekly Progress - ") .. ((ns.L and ns.L["COMPLETE_LABEL"]) or "Complete"))
    else
        titleText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        local displayContent = plan.contentName or "Midnight"
        if displayContent == "" then displayContent = "Midnight" end
        titleText:SetText(((ns.L and ns.L["DAILY_TASKS_PREFIX"]) or "Weekly Progress - ") .. displayContent)
    end
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    
    local charText = FontManager:CreateFontString(card, "body", "OVERLAY")
    charText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    charText:SetTextColor(classColor[1], classColor[2], classColor[3])
    local charDisplay = plan.characterName or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    if plan.characterRealm and plan.characterRealm ~= "" then
        local rShown = (ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(plan.characterRealm)) or plan.characterRealm
        charDisplay = charDisplay .. " - " .. rShown
    end
    charText:SetText(charDisplay)
    
    -- Delete button
    local removeBtn = ns.UI.Factory:CreateButton(card, 20, 20, true)
    removeBtn:SetPoint("TOPRIGHT", -8, -8)
    removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    removeBtn:SetScript("OnClick", function()
        WarbandNexus:RemovePlan(plan.id)
    end)
    
    -- Alert button
    local hasReminderDQ = WarbandNexus.HasPlanReminder and WarbandNexus:HasPlanReminder(plan.id)
    local hasActiveReminderDQ = WarbandNexus.HasActiveReminder and WarbandNexus:HasActiveReminder(plan.id)
    local alertBtnDQ = ns.UI.Factory:CreateButton(card, 20, 20, true)
    alertBtnDQ:SetPoint("TOPRIGHT", -60, -8)
    local bellTexDQ = alertBtnDQ:CreateTexture(nil, "ARTWORK")
    bellTexDQ:SetSize(18, 18)
    bellTexDQ:SetPoint("CENTER")
    bellTexDQ:SetAtlas("minimap-genericevent-hornicon-small", true)
    if hasActiveReminderDQ then
        bellTexDQ:SetVertexColor(1, 0.6, 0)
    elseif hasReminderDQ then
        bellTexDQ:SetVertexColor(1, 0.82, 0)
    else
        bellTexDQ:SetVertexColor(0.5, 0.5, 0.5)
    end
    alertBtnDQ._bellTex = bellTexDQ

    if hasActiveReminderDQ then
        local pulseAG = alertBtnDQ:CreateAnimationGroup()
        pulseAG:SetLooping("BOUNCE")
        local pulseAnim = pulseAG:CreateAnimation("Alpha")
        pulseAnim:SetFromAlpha(1)
        pulseAnim:SetToAlpha(0.3)
        pulseAnim:SetDuration(0.8)
        pulseAnim:SetSmoothing("IN_OUT")
        pulseAG:Play()
        alertBtnDQ._pulseAG = pulseAG
    end

    alertBtnDQ:SetScript("OnClick", function()
        if hasActiveReminderDQ and WarbandNexus.DismissReminders then
            WarbandNexus:DismissReminders(plan.id)
            return
        end
        if WarbandNexus.ShowSetAlertDialog then
            WarbandNexus:ShowSetAlertDialog(plan.id)
        end
    end)
    alertBtnDQ:SetScript("OnEnter", function(btn)
        if btn._bellTex then btn._bellTex:SetVertexColor(1, 0.9, 0.3) end
        if btn._pulseAG then btn._pulseAG:Stop(); btn:SetAlpha(1) end
        local tooltipTitle, tooltipLines
        local activeReminders = WarbandNexus.GetActiveReminders and WarbandNexus:GetActiveReminders(plan.id)
        if activeReminders then
            tooltipTitle = (ns.L and ns.L["REMINDER_PREFIX"]) or "Reminder"
            tooltipLines = {}
            for _, label in ipairs(activeReminders) do
                tooltipLines[#tooltipLines + 1] = { text = "|cffffd100" .. label .. "|r" }
            end
            tooltipLines[#tooltipLines + 1] = { text = " " }
            tooltipLines[#tooltipLines + 1] = { text = "|cff888888" .. ((ns.L and ns.L["CLICK_TO_DISMISS"]) or "Click to dismiss") .. "|r" }
        else
            tooltipTitle = hasReminderDQ and ((ns.L and ns.L["ALERT_ACTIVE"]) or "Alert Active") or ((ns.L and ns.L["SET_ALERT"]) or "Set Alert")
            tooltipLines = {}
        end
        if ns.TooltipService then
            ns.TooltipService:Show(btn, { type = "custom", title = tooltipTitle, icon = false, anchor = "ANCHOR_TOP", lines = tooltipLines })
        end
    end)
    alertBtnDQ:SetScript("OnLeave", function(btn)
        if btn._pulseAG then btn._pulseAG:Play() end
        if btn._bellTex then
            local activeNow = WarbandNexus.HasActiveReminder and WarbandNexus:HasActiveReminder(plan.id)
            local reminderSet = WarbandNexus.HasPlanReminder and WarbandNexus:HasPlanReminder(plan.id)
            if activeNow then
                btn._bellTex:SetVertexColor(1, 0.6, 0)
            elseif reminderSet then
                btn._bellTex:SetVertexColor(1, 0.82, 0)
            else
                btn._bellTex:SetVertexColor(0.5, 0.5, 0.5)
            end
        end
        if ns.TooltipService then ns.TooltipService:Hide() end
    end)
    
    -- === CATEGORY PROGRESS SLOTS ===
    local contentY = -70
    local cardWidth = card:GetWidth()
    local availableWidth = cardWidth - 10 - 15
    local slotSpacing = 8
    
    local catDisplay = ns.CATEGORY_DISPLAY or {}
    local shortNames = {
        weeklyQuests = (ns.L and ns.L["QUEST_CAT_WEEKLY"])        or "Weekly",
        worldQuests  = (ns.L and ns.L["QUEST_CAT_WORLD"])         or "World",
        dailyQuests  = (ns.L and ns.L["QUEST_CAT_DAILY"])         or "Daily",
        events       = (ns.L and ns.L["QUEST_CAT_CONTENT_EVENTS"]) or "Events",
    }
    local categoryInfo = {}
    for key, display in pairs(catDisplay) do
        categoryInfo[key] = {
            name  = shortNames[key] or key,
            atlas = display.atlas,
            color = display.color,
        }
    end
    
    local visibleSlots = {}
    for _, catKey in ipairs(categoryOrder) do
        if plan.questTypes and plan.questTypes[catKey] then
            local questList = plan.quests and plan.quests[catKey] or {}
            local completed, total = 0, 0
            for _, q in ipairs(questList) do
                if not q.isSubQuest then
                    total = total + 1
                    if q.isComplete then completed = completed + 1 end
                end
            end
            -- Always include tracked categories so the user sees them even when the
            -- live scan hasn't found any active quests yet (e.g. Midnight Assignments
            -- not yet unlocked or between weekly resets).
            visibleSlots[#visibleSlots + 1] = {
                key     = catKey,
                info    = categoryInfo[catKey],
                completed = completed,
                total   = total,
                isEmpty = (total == 0),
            }
        end
    end

    local visibleCount = #visibleSlots
    if visibleCount == 0 then return end
    
    local slotWidth = (availableWidth - slotSpacing * math.max(0, visibleCount - 1)) / visibleCount
    local slotHeight = 92
    
    for slotIndex, slot in ipairs(visibleSlots) do
        local slotX = 10 + (slotIndex - 1) * (slotWidth + slotSpacing)
        local ci = slot.info
        
        local slotFrame = ns.UI.Factory:CreateContainer(card, slotWidth, slotHeight)
        slotFrame:SetPoint("TOPLEFT", slotX, contentY)
        
        local isEmpty = slot.isEmpty
        -- Dim alpha for empty/untracked categories so they look visually distinct
        -- from categories with active content.
        if isEmpty then
            slotFrame:SetAlpha(0.45)
        end

        -- Category icon
        local catIcon = slotFrame:CreateTexture(nil, "ARTWORK")
        catIcon:SetSize(22, 22)
        catIcon:SetPoint("TOP", 0, -6)
        pcall(catIcon.SetAtlas, catIcon, ci.atlas, false)
        if isEmpty then
            catIcon:SetVertexColor(0.5, 0.5, 0.5)
        end

        -- Title
        local title = FontManager:CreateFontString(slotFrame, "body", "OVERLAY")
        title:SetPoint("TOP", catIcon, "BOTTOM", 0, -2)
        title:SetText(ci.name)
        if isEmpty then
            title:SetTextColor(0.5, 0.5, 0.5)
        else
            title:SetTextColor(ci.color[1], ci.color[2], ci.color[3])
        end

        -- Progress bar
        local barY = -52
        local barPadding = 12
        local barWidth = slotWidth - (barPadding * 2)
        local barHeight = 14

        local barBg = ns.UI.Factory:CreateContainer(slotFrame, barWidth, barHeight)
        barBg:SetPoint("TOP", slotFrame, "TOP", 0, barY)

        if ApplyVisuals then
            if isEmpty then
                ApplyVisuals(barBg, {0.05, 0.05, 0.07, 0.2}, {0.3, 0.3, 0.3, 0.3})
            else
                ApplyVisuals(barBg, {0.05, 0.05, 0.07, 0.3}, {ci.color[1], ci.color[2], ci.color[3], 0.6})
            end
        end

        if not isEmpty then
            local fillPercent = slot.total > 0 and math.min(1.0, slot.completed / slot.total) or 0
            local innerBarWidth = barWidth - 2
            local fillWidth = innerBarWidth * fillPercent
            if fillWidth > 0 then
                local fill = barBg:CreateTexture(nil, "ARTWORK")
                fill:SetPoint("LEFT", barBg, "LEFT", 1, 0)
                fill:SetSize(fillWidth, barHeight - 2)
                fill:SetTexture("Interface\\Buttons\\WHITE8x8")
                fill:SetVertexColor(ci.color[1], ci.color[2], ci.color[3], 1)
            end
        end

        -- Progress text below bar
        local progressLabel = FontManager:CreateFontString(slotFrame, "title", "OVERLAY")
        progressLabel:SetPoint("TOP", barBg, "BOTTOM", 0, -6)
        if isEmpty then
            progressLabel:SetTextColor(0.4, 0.4, 0.4)
            progressLabel:SetText("—")
        elseif slot.completed == slot.total and slot.total > 0 then
            progressLabel:SetTextColor(0.3, 1, 0.3)
            progressLabel:SetText(string.format("%d / %d", slot.completed, slot.total))
        else
            progressLabel:SetTextColor(1, 1, 1)
            progressLabel:SetText(string.format("%d / %d", slot.completed, slot.total))
        end
    end
end

--[[
    Create Add Button
    @param parent Frame - Parent frame
    @param options table - Configuration options:
        - width: number (default from BUTTON_SIZES)
        - height: number (default from BUTTON_SIZES)
        - label: string (default "+ Add")
        - anchorPoint: string (default "BOTTOMRIGHT")
        - x: number (default -10)
        - y: number (default 10)
        - buttonType: string "row" or "card" (default "card")
        - onClick: function - Callback when button is clicked
    @return Frame - Button frame
]]
function PlanCardFactory.CreateAddButton(parent, options)
    options = options or {}
    local BUTTON_SIZES = ns.UI_BUTTON_SIZES or {ROW = {width = 70, height = 28}, CARD = {width = 24, height = 24}}
    local buttonType = options.buttonType or "card"
    local defaultSize = buttonType == "row" and BUTTON_SIZES.ROW or BUTTON_SIZES.CARD
    
    -- Use standardized card button layout constants
    local CBL = ns.UI_CARD_BUTTON_LAYOUT or {ADD_WIDTH = 60, ADD_HEIGHT = 32, ADD_MARGIN_X = 10, ADD_MARGIN_Y = 8}
    -- Increase hit area: Make button wider for easier clicking
    local width = options.width or (buttonType == "row" and defaultSize.width or CBL.ADD_WIDTH)
    local height = options.height or (buttonType == "row" and defaultSize.height or CBL.ADD_HEIGHT)
    -- Standardized label for all button types
    local label = options.label or ((ns.L and ns.L["ADD_BUTTON"]) or "+ Add")
    local anchorPoint = options.anchorPoint or (buttonType == "row" and "RIGHT" or "BOTTOMRIGHT")
    -- CARD: Position in bottom-right with symmetrical padding
    local x = options.x or (buttonType == "row" and -8 or -CBL.ADD_MARGIN_X)
    local y = options.y or (buttonType == "row" and 0 or CBL.ADD_MARGIN_Y)
    
    -- Create borderless button (using Factory pattern, just text with hover)
    local addBtn = ns.UI.Factory:CreateButton(parent, width, height, true)  -- noBorder=true
    addBtn:SetPoint(anchorPoint, x, y)
    addBtn:SetFrameLevel(parent:GetFrameLevel() + 10)
    addBtn:EnableMouse(true)
    addBtn:RegisterForClicks("LeftButtonUp")
    
    -- Extend hit rect insets for even easier clicking (8px padding on all sides)
    addBtn:SetHitRectInsets(-8, -8, -8, -8)
    
    -- Create text (no background, no border)
    local FontManager = ns.FontManager
    local btnText = FontManager:CreateFontString(addBtn, "body", "OVERLAY")
    -- CENTER text in wider button for better UX
    if buttonType == "card" then
        btnText:SetPoint("CENTER", 0, 0)  -- Centered in wider button (easier to click)
    else
        btnText:SetPoint("CENTER")  -- Row type: also centered
    end
    btnText:SetText(label)
    btnText:SetTextColor(0.4, 0.8, 1, 1)  -- Accent color (blue)
    addBtn.text = btnText
    
    -- Hover effect (text color change only)
    addBtn:SetScript("OnEnter", function(self)
        self.text:SetTextColor(0.6, 0.9, 1, 1)  -- Lighter blue on hover
    end)
    
    addBtn:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.4, 0.8, 1, 1)  -- Back to normal
    end)
    
    -- Prevent click propagation
    addBtn:SetScript("OnMouseDown", function(self, button)
        -- Stop propagation
    end)
    
    if options.onClick then
        addBtn:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                options.onClick(self)
            end
        end)
    end
    
    return addBtn
end

--[[
    Create Added Indicator
    @param parent Frame - Parent frame
    @param options table - Configuration options:
        - width: number (default from BUTTON_SIZES)
        - height: number (default from BUTTON_SIZES)
        - label: string (default "Added")
        - fontCategory: string (default "body")
        - anchorPoint: string (default "BOTTOMRIGHT")
        - x: number (default -10)
        - y: number (default 10)
        - buttonType: string "row" or "card" (default "card")
    @return Frame - Indicator frame
]]
function PlanCardFactory.CreateAddedIndicator(parent, options)
    options = options or {}
    local BUTTON_SIZES = ns.UI_BUTTON_SIZES or {ROW = {width = 70, height = 28}, CARD = {width = 24, height = 24}}
    local buttonType = options.buttonType or "card"
    local defaultSize = buttonType == "row" and BUTTON_SIZES.ROW or BUTTON_SIZES.CARD
    
    -- Use standardized card button layout constants (match Add button)
    local CBL = ns.UI_CARD_BUTTON_LAYOUT or {ADD_WIDTH = 60, ADD_HEIGHT = 32, ADD_MARGIN_X = 10, ADD_MARGIN_Y = 8}
    -- Match Add button size for consistent layout
    local width = options.width or (buttonType == "row" and defaultSize.width or CBL.ADD_WIDTH)
    local height = options.height or (buttonType == "row" and defaultSize.height or CBL.ADD_HEIGHT)
    local label = options.label or ((ns.L and ns.L["ADDED_LABEL"]) or "Added")
    local fontCategory = options.fontCategory or "body"  -- Default to "body" for consistency
    local anchorPoint = options.anchorPoint or (buttonType == "row" and "RIGHT" or "BOTTOMRIGHT")
    -- CARD: Match Add button position with symmetrical padding
    local x = options.x or (buttonType == "row" and -8 or -CBL.ADD_MARGIN_X)
    local y = options.y or (buttonType == "row" and 0 or CBL.ADD_MARGIN_Y)
    
    local ICON_CHECK = "common-icon-checkmark"
    
    -- Create frame (using Factory pattern)
    local addedFrame = ns.UI.Factory:CreateContainer(parent, width, height)
    addedFrame:SetPoint(anchorPoint, x, y)
    
    -- Create text first (centered in frame, offset right for icon room)
    local addedText = FontManager:CreateFontString(addedFrame, fontCategory, "OVERLAY")
    addedText:SetPoint("CENTER", addedFrame, "CENTER", 9, 0)  -- offset right by ~half icon width
    addedText:SetText("|cff44ff44" .. label .. "|r")
    
    -- Create checkmark icon (14px size, isAtlas=true, noBorder=true), anchored left of text
    local addedIcon = CreateIcon(addedFrame, ICON_CHECK, 14, true, nil, true)
    addedIcon:SetPoint("RIGHT", addedText, "LEFT", -2, 0)
    addedIcon:Show()
    
    return addedFrame
end

--[[
    Create source text display (simplified - no achievement linking)
    @param parent Frame - Parent container
    @param item table - Item data {source}
    @param currentY number - Y offset for positioning
    @return FontString - Created text element for anchoring
]]
function PlanCardFactory:CreateSourceText(parent, item, currentY)
    if not parent or not item then return nil end
    
    local sourceText = FontManager:CreateFontString(parent, "body", "OVERLAY")
    local SOURCE_RIGHT_PAD = (ns.UI_CARD_BUTTON_LAYOUT and ns.UI_CARD_BUTTON_LAYOUT.SOURCE_RIGHT_PAD) or 80
    sourceText:SetPoint("TOPLEFT", 10, currentY)
    sourceText:SetPoint("RIGHT", parent, "RIGHT", -SOURCE_RIGHT_PAD, 0)
    
    -- Resolve empty source from API for browser items (mount/pet) so "Unknown source" is avoided.
    local rawText = item.source or ""
    if type(rawText) ~= "string" or (issecretvalue and issecretvalue(rawText)) then
        rawText = ""
    end
    if IsPlaceholderSourceText(rawText) and item.id and WarbandNexus and WarbandNexus.GetPlanDisplaySource then
        local planLike = { type = item.category or "mount", mountID = (item.category == "mount") and item.id or nil, speciesID = (item.category == "pet") and item.id or nil, itemID = (item.category == "toy") and item.id or nil, sourceID = (item.category == "illusion") and item.id or nil }
        if planLike.mountID or planLike.speciesID or planLike.itemID or planLike.sourceID then
            local resolved = WarbandNexus:GetPlanDisplaySource(planLike)
            if resolved and type(resolved) == "string" and not (issecretvalue and issecretvalue(resolved)) and resolved ~= "" then
                rawText = resolved
            end
        end
    end
    if rawText ~= "" and WarbandNexus.CleanSourceText then
        rawText = WarbandNexus:CleanSourceText(rawText)
        if type(rawText) ~= "string" or (issecretvalue and issecretvalue(rawText)) then
            rawText = ""
        end
    end
    -- Replace newlines with spaces and collapse whitespace
    if rawText ~= "" then
        rawText = rawText:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    end
    
    -- If no valid source text, show default message
    if rawText == "" or rawText == "Unknown" then
        rawText = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
    end
    
    local P = ns.PLAN_UI_COLORS or {}
    local srcLabel = P.sourceLabel or "|cff99ccff"
    local body = P.body or "|cffffffff"
    -- Check if text already has a source type prefix (Vendor:, Drop:, Quest:, etc.)
    local sourceType, sourceDetail = rawText:match("^([^:]+:%s*)(.*)$")
    if sourceType and sourceDetail and sourceDetail ~= "" then
        local iconAtlas = PlanSourceIconMarkup("class") .. " "
        local lowerType = (not (issecretvalue and issecretvalue(sourceType))) and string.lower(sourceType) or ""
        if lowerType:match("quest") then
            iconAtlas = PlanSourceIconMarkup("quest") .. " "
        elseif lowerType:match("profession") or lowerType:match("crafted") then
            iconAtlas = string.format("|A:Repair:%d:%d|a ", PLAN_SRC_ICON_LG, PLAN_SRC_ICON_LG)
        elseif lowerType:match("drop") or lowerType:match("loot") then
            iconAtlas = PlanSourceIconMarkup("loot") .. " "
        elseif lowerType:match("location") or lowerType:match("zone") then
            iconAtlas = PlanSourceIconMarkup("location") .. " "
        end
        sourceText:SetText(iconAtlas .. srcLabel .. NormalizeColonLabelSpacing(sourceType) .. "|r" .. body .. sourceDetail .. "|r")
    else
        sourceText:SetText(PlanSourceIconMarkup("class") .. " " .. srcLabel .. NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:") .. "|r " .. body .. rawText .. "|r")
    end
    
    sourceText:SetJustifyH("LEFT")
    sourceText:SetWordWrap(true)
    sourceText:SetMaxLines(2)
    sourceText:SetNonSpaceWrap(false)
    
    return sourceText
end

-- Export
PlanCardFactory.TYPE_ICONS = TYPE_ICONS  -- Export atlas mapping for use in other modules
PlanCardFactory.TYPE_NAMES = TYPE_NAMES
PlanCardFactory.TYPE_COLORS = TYPE_COLORS
ns.UI_PlanCardFactory = PlanCardFactory
