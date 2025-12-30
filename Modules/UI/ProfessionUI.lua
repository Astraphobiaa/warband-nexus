--[[
    Warband Nexus - Profession UI Module
    Display profession progress, specializations, and traits for all characters
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local function GetCOLORS()
    return ns.UI_COLORS
end

-- Performance: Local function references
local format = string.format

-- Expand/Collapse State Management
local expandedStates = {}

-- Initialize spec tree expanded states in namespace
if not ns.expandedSpecTrees then
    ns.expandedSpecTrees = {}
end

local function IsExpanded(key, defaultState)
    if expandedStates[key] == nil then
        expandedStates[key] = defaultState
    end
    return expandedStates[key]
end

local function ToggleExpand(key, newState)
    expandedStates[key] = newState
    WarbandNexus:RefreshUI()
end

--============================================================================
-- DRAW PROFESSION PROGRESS
--============================================================================

function WarbandNexus:DrawProfessionProgress(parent)
    -- Safety check to prevent taint
    if InCombatLockdown() then
        local warningText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        warningText:SetPoint("CENTER", 0, 0)
        warningText:SetTextColor(1, 0.5, 0)
        warningText:SetText("Cannot display profession UI while in combat")
        return 100
    end
    
    local yOffset = 8 -- Top padding
    local width = parent:GetWidth() - 20
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    
    -- Get current player key
    local currentPlayerName = UnitName("player")
    local currentPlayerRealm = GetRealmName()
    local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
    
    -- Sort characters (same logic as PvE tab)
    local currentChar = nil
    local favorites = {}
    local regular = {}
    
    for _, char in ipairs(characters) do
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        
        if charKey == currentPlayerKey then
            currentChar = char
        elseif self:IsFavoriteCharacter(charKey) then
            table.insert(favorites, char)
        else
            table.insert(regular, char)
        end
    end
    
    -- Simple sort function
    local function sortCharacters(list)
        table.sort(list, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then
                return (a.level or 0) > (b.level or 0)
            else
                return (a.name or ""):lower() < (b.name or ""):lower()
            end
        end)
        return list
    end
    
    favorites = sortCharacters(favorites)
    regular = sortCharacters(regular)
    
    -- Merge: Current first, then favorites, then regular
    local sortedCharacters = {}
    if currentChar then
        table.insert(sortedCharacters, currentChar)
    end
    for _, char in ipairs(favorites) do
        table.insert(sortedCharacters, char)
    end
    for _, char in ipairs(regular) do
        table.insert(sortedCharacters, char)
    end
    characters = sortedCharacters
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Professions|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Track profession skills, specializations, and knowledge points")
    
    -- Scan button (right side)
    local scanBtn = CreateFrame("Button", nil, titleCard, "UIPanelButtonTemplate")
    scanBtn:SetSize(90, 28)
    scanBtn:SetPoint("RIGHT", -15, 0)
    scanBtn:SetText("Scan All")
    scanBtn:SetScript("OnClick", function()
        WarbandNexus:ScanProfessionData()
    end)
    scanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Scan Professions")
        GameTooltip:AddLine("Opens each profession window to collect detailed data", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    yOffset = yOffset + 75
    
    -- ===== INFO CARD (Help Message) =====
    local hasAnyData = false
    for _, char in ipairs(characters) do
        if char.professions and (char.professions[1] or char.professions[2]) then
            local prof = char.professions[1] or char.professions[2]
            if prof.expansions and #prof.expansions > 0 then
                hasAnyData = true
                break
            end
        end
    end
    
    if not hasAnyData and #characters > 0 then
        local infoCard = CreateCard(parent, 60)
        infoCard:SetPoint("TOPLEFT", 10, -yOffset)
        infoCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local infoIcon = infoCard:CreateTexture(nil, "ARTWORK")
        infoIcon:SetSize(24, 24)
        infoIcon:SetPoint("LEFT", 15, 0)
        infoIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        infoIcon:SetVertexColor(0.3, 0.7, 1.0)
        
        local infoText = infoCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        infoText:SetPoint("LEFT", infoIcon, "RIGHT", 10, 5)
        infoText:SetTextColor(0.9, 0.9, 0.9)
        infoText:SetText("First time? Open each profession window once to collect detailed data")
        
        local hintText = infoCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hintText:SetPoint("LEFT", infoIcon, "RIGHT", 10, -12)
        hintText:SetTextColor(0.6, 0.6, 0.6)
        hintText:SetText("Press 'P' to open professions, or use the 'Scan All' button above")
        
        yOffset = yOffset + 65
    end
    
    -- ===== EMPTY STATE =====
    if #characters == 0 then
        local emptyIcon = parent:CreateTexture(nil, "ARTWORK")
        emptyIcon:SetSize(64, 64)
        emptyIcon:SetPoint("TOP", 0, -yOffset - 50)
        emptyIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
        emptyIcon:SetDesaturated(true)
        emptyIcon:SetAlpha(0.4)
        
        local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        emptyText:SetPoint("TOP", 0, -yOffset - 130)
        emptyText:SetText("|cff666666No Characters Found|r")
        
        local emptyDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyDesc:SetPoint("TOP", 0, -yOffset - 160)
        emptyDesc:SetTextColor(0.6, 0.6, 0.6)
        emptyDesc:SetText("Log in to any character to start tracking professions")
        
        return yOffset + 240
    end
    
    -- ===== CHARACTER COLLAPSIBLE HEADERS =====
    for i, char in ipairs(characters) do
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        local isFavorite = self:IsFavoriteCharacter(charKey)
        local professions = char.professions or {}
        
        -- Get profession summary
        local hasProfessions = (professions[1] or professions[2]) ~= nil
        
        -- Smart expand: current character with professions
        local charExpandKey = "profession-char-" .. charKey
        local isCurrentChar = (charKey == currentPlayerKey)
        local charExpanded = IsExpanded(charExpandKey, isCurrentChar and hasProfessions)
        
        -- Create collapsible header
        local charHeader, charBtn = CreateCollapsibleHeader(
            parent,
            "",
            charExpandKey,
            charExpanded,
            function(isExpanded) ToggleExpand(charExpandKey, isExpanded) end
        )
        charHeader:SetPoint("TOPLEFT", 10, -yOffset)
        charHeader:SetPoint("TOPRIGHT", -10, -yOffset)
        
        yOffset = yOffset + 35
        
        -- Favorite button
        local favButton = CreateFrame("Button", nil, charHeader)
        favButton:SetSize(18, 18)
        favButton:SetPoint("LEFT", charBtn, "RIGHT", 4, 0)
        
        local favIcon = favButton:CreateTexture(nil, "ARTWORK")
        favIcon:SetAllPoints()
        if isFavorite then
            favIcon:SetTexture("Interface\\COMMON\\FavoritesIcon")
            favIcon:SetDesaturated(false)
            favIcon:SetVertexColor(1, 0.84, 0)
        else
            favIcon:SetTexture("Interface\\COMMON\\FavoritesIcon")
            favIcon:SetDesaturated(true)
            favIcon:SetVertexColor(0.5, 0.5, 0.5)
        end
        favButton.icon = favIcon
        favButton.charKey = charKey
        
        favButton:SetScript("OnClick", function(btn)
            local newStatus = WarbandNexus:ToggleFavoriteCharacter(btn.charKey)
            if newStatus then
                btn.icon:SetDesaturated(false)
                btn.icon:SetVertexColor(1, 0.84, 0)
            else
                btn.icon:SetDesaturated(true)
                btn.icon:SetVertexColor(0.5, 0.5, 0.5)
            end
            WarbandNexus:RefreshUI()
        end)
        
        favButton:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            if isFavorite then
                GameTooltip:SetText("|cffffd700Favorite|r\nClick to remove")
            else
                GameTooltip:SetText("Add to favorites")
            end
            GameTooltip:Show()
        end)
        favButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        -- Character name text
        local charNameText = charHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        charNameText:SetPoint("LEFT", favButton, "RIGHT", 6, 0)
        charNameText:SetText(string.format("|cff%02x%02x%02x%s|r |cff888888Lv %d|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.name, char.level or 1))
        
        -- Profession icons (right side)
        if professions[1] or professions[2] then
            local iconContainer = CreateFrame("Frame", nil, charHeader)
            iconContainer:SetSize(60, 24)
            iconContainer:SetPoint("RIGHT", -10, 0)
            
            local xOffset = 0
            for _, prof in ipairs({professions[1], professions[2]}) do
                if prof then
                    local icon = iconContainer:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(20, 20)
                    icon:SetPoint("LEFT", xOffset, 0)
                    
                    if prof.icon then
                        icon:SetTexture(prof.icon)
                    else
                        icon:SetTexture(self:GetProfessionIcon(prof.name))
                    end
                    
                    xOffset = xOffset + 24
                end
            end
        end
        
        -- Cards (only when expanded)
        if charExpanded then
            local cardContainer = CreateFrame("Frame", nil, parent)
            cardContainer:SetPoint("TOPLEFT", 10, -yOffset)
            cardContainer:SetPoint("TOPRIGHT", -10, -yOffset)
            
            local totalWidth = parent:GetWidth() - 20
            local cardHeight = 220
            
            -- Calculate card widths based on number of professions
            local numPrimaryProfs = 0
            if professions[1] then numPrimaryProfs = numPrimaryProfs + 1 end
            if professions[2] then numPrimaryProfs = numPrimaryProfs + 1 end
            
            if numPrimaryProfs == 0 then
                -- No professions learned
                local noProfCard = CreateCard(cardContainer, 120)
                noProfCard:SetPoint("TOPLEFT", 0, 0)
                noProfCard:SetPoint("TOPRIGHT", 0, 0)
                
                local noProfIcon = noProfCard:CreateTexture(nil, "ARTWORK")
                noProfIcon:SetSize(32, 32)
                noProfIcon:SetPoint("CENTER", 0, 10)
                noProfIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
                noProfIcon:SetDesaturated(true)
                noProfIcon:SetAlpha(0.3)
                
                local noProfText = noProfCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                noProfText:SetPoint("CENTER", 0, -20)
                noProfText:SetTextColor(0.6, 0.6, 0.6)
                noProfText:SetText("No professions learned")
                
                local hintText = noProfCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                hintText:SetPoint("CENTER", 0, -40)
                hintText:SetTextColor(0.5, 0.5, 0.5)
                hintText:SetText("Learn a profession to track progress")
                
                cardContainer:SetHeight(120)
                yOffset = yOffset + 130
            else
                -- Create profession cards with proper spacing
                local cardGap = 5 -- Gap between cards
                local totalGaps = (numPrimaryProfs - 1) * cardGap
                local cardWidth = (totalWidth - totalGaps) / numPrimaryProfs
                local currentX = 0
                
                for profIndex = 1, 2 do
                    local prof = professions[profIndex]
                    if prof then
                        local profCard = self:CreateProfessionCard(cardContainer, prof, charKey)
                        profCard:SetPoint("TOPLEFT", currentX, 0)
                        profCard:SetSize(cardWidth, cardHeight)
                        
                        currentX = currentX + cardWidth + cardGap
                    end
                end
                
                cardContainer:SetHeight(cardHeight)
                yOffset = yOffset + cardHeight + 10
                
                -- Show expanded spec trees if any
                for profIndex = 1, 2 do
                    local prof = professions[profIndex]
                    if prof and self:HasProfessionSpecs(prof) then
                        local expandKey = charKey .. "-" .. prof.name .. "-tree"
                        if ns.expandedSpecTrees and ns.expandedSpecTrees[expandKey] then
                            -- Find the first spec with nodes
                            local firstSpec = nil
                            if prof.specializations and prof.specializations.specs then
                                for _, spec in pairs(prof.specializations.specs) do
                                    if spec.nodes and #spec.nodes > 0 then
                                        firstSpec = spec
                                        break
                                    end
                                end
                            end
                            
                            if firstSpec then
                                local treeFrame = self:CreateSpecTreeCanvas(parent, firstSpec, charKey, prof.name)
                                treeFrame:SetPoint("TOPLEFT", 10, -yOffset)
                                treeFrame:SetPoint("TOPRIGHT", -10, -yOffset)
                                yOffset = yOffset + treeFrame:GetHeight() + 10
                            end
                        end
                    end
                end
            end
        end
        
        yOffset = yOffset + 5
    end
    
    return yOffset + 20
end

--============================================================================
-- CREATE PROFESSION CARD
--============================================================================

function WarbandNexus:CreateProfessionCard(parent, profession, charKey)
    -- Prevent taint issues
    if InCombatLockdown() then
        return CreateFrame("Frame", nil, parent)
    end
    
    local card = CreateCard(parent, 220)
    
    local yPos = 15
    
    -- Profession icon and name
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 15, -yPos)
    
    if profession.icon then
        icon:SetTexture(profession.icon)
    else
        icon:SetTexture(self:GetProfessionIcon(profession.name))
    end
    
    local nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("LEFT", icon, "RIGHT", 10, 5)
    nameText:SetText(profession.name or "Unknown")
    
    -- Skill level
    local r, g, b = self:GetProfessionColor(profession.rank, profession.maxRank)
    local skillText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skillText:SetPoint("LEFT", icon, "RIGHT", 10, -10)
    skillText:SetText(string.format("|cff%02x%02x%02xSkill: %d / %d|r", 
        r * 255, g * 255, b * 255,
        profession.rank or 0, profession.maxRank or 0))
    
    yPos = yPos + 45
    
    -- Expansions (if available)
    if profession.expansions and #profession.expansions > 0 then
        local expHeader = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        expHeader:SetPoint("TOPLEFT", 15, -yPos)
        expHeader:SetText("|cffffcc00Expansions|r")
        expHeader:SetTextColor(1, 0.8, 0)
        
        yPos = yPos + 18
        
        -- Show top 3 expansions
        local shownCount = 0
        for i, exp in ipairs(profession.expansions) do
            if shownCount >= 3 then break end
            
            local expText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            expText:SetPoint("TOPLEFT", 20, -yPos)
            
            local expR, expG, expB = self:GetProfessionColor(exp.rank, exp.maxRank)
            expText:SetText(string.format("%s: |cff%02x%02x%02x%d/%d|r", 
                exp.name or "Unknown",
                expR * 255, expG * 255, expB * 255,
                exp.rank or 0, exp.maxRank or 0))
            
            yPos = yPos + 15
            shownCount = shownCount + 1
        end
        
        yPos = yPos + 5
    end
    
    -- Specializations (if available)
    if self:HasProfessionSpecs(profession) then
        local specHeader = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        specHeader:SetPoint("TOPLEFT", 15, -yPos)
        specHeader:SetText("|cffffcc00Specializations|r")
        specHeader:SetTextColor(1, 0.8, 0)
        
        yPos = yPos + 18
        
        local spent, total = self:GetProfessionKnowledge(profession)
        
        local knowledgeText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        knowledgeText:SetPoint("TOPLEFT", 20, -yPos)
        
        local kR = spent > 0 and 0.3 or 0.6
        local kG = spent > 0 and 0.9 or 0.6
        local kB = spent > 0 and 0.3 or 0.6
        knowledgeText:SetText(string.format("|cff%02x%02x%02xKnowledge: %d / %d|r",
            kR * 255, kG * 255, kB * 255, spent, total))
        
        yPos = yPos + 20
        
        -- Show spec trees (compact list)
        local specCount = 0
        if profession.specializations.specs then
            for specIndex, spec in pairs(profession.specializations.specs) do
                if type(specIndex) == "number" and yPos < 185 then
                    local specText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    specText:SetPoint("TOPLEFT", 25, -yPos)
                    
                    local specR, specG, specB = self:GetProfessionColor(spec.knowledgeSpent, spec.knowledgeMax)
                    specText:SetText(string.format("• %s: |cff%02x%02x%02x%d/%d|r",
                        spec.name or ("Spec " .. specIndex),
                        specR * 255, specG * 255, specB * 255,
                        spec.knowledgeSpent or 0,
                        spec.knowledgeMax or 0))
                    
                    yPos = yPos + 15
                    specCount = specCount + 1
                end
            end
        end
        
        -- Show Spec Tree button (if specs available)
        if specCount > 0 and yPos < 200 then
            local showTreeBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
            showTreeBtn:SetSize(120, 22)
            showTreeBtn:SetPoint("BOTTOM", 0, 10)
            showTreeBtn:SetText("Show Spec Tree")
            showTreeBtn:SetScript("OnClick", function()
                -- Toggle spec tree display
                local expandKey = charKey .. "-" .. profession.name .. "-tree"
                if not ns.expandedSpecTrees then
                    ns.expandedSpecTrees = {}
                end
                ns.expandedSpecTrees[expandKey] = not ns.expandedSpecTrees[expandKey]
                WarbandNexus:RefreshUI()
            end)
        end
    end
    
    -- Recipe count (if available)
    if profession.recipes and profession.recipes.learned then
        local recipeCount = #profession.recipes.learned
        if recipeCount > 0 and yPos < 200 then
            local recipeText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            recipeText:SetPoint("TOPLEFT", 15, -yPos)
            recipeText:SetText(string.format("|cffffcc00Recipes:|r |cffffffff%d learned|r", recipeCount))
            yPos = yPos + 18
        end
    end
    
    -- Show help text if no data
    if not profession.expansions or #profession.expansions == 0 then
        if yPos < 150 then
            local helpFrame = CreateFrame("Frame", nil, card)
            helpFrame:SetSize(180, 60)
            helpFrame:SetPoint("CENTER", 0, -20)
            
            local helpIcon = helpFrame:CreateTexture(nil, "ARTWORK")
            helpIcon:SetSize(20, 20)
            helpIcon:SetPoint("TOP", 0, 0)
            helpIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            helpIcon:SetDesaturated(true)
            helpIcon:SetAlpha(0.4)
            
            local helpText = helpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            helpText:SetPoint("TOP", helpIcon, "BOTTOM", 0, -6)
            helpText:SetTextColor(0.7, 0.7, 0.7)
            helpText:SetText("No detailed data")
            helpText:SetWordWrap(true)
            helpText:SetWidth(160)
            helpText:SetJustifyH("CENTER")
            
            local scanHint = helpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            scanHint:SetPoint("TOP", helpText, "BOTTOM", 0, -4)
            scanHint:SetTextColor(0.5, 0.5, 0.5)
            scanHint:SetText("Open profession window")
            scanHint:SetWordWrap(true)
            scanHint:SetWidth(160)
            scanHint:SetJustifyH("CENTER")
        end
    end
    
    return card
end

