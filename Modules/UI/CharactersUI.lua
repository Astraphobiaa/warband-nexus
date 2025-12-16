--[[
    Warband Nexus - Characters Tab
    Display all tracked characters with gold, level, and last seen info
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local CreateSortableTableHeader = ns.UI_CreateSortableTableHeader

--============================================================================
-- DRAW CHARACTER LIST
--============================================================================

function WarbandNexus:DrawCharacterList(parent)
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    
    -- Sorting state (persisted across refreshes)
    if not parent.sortKey then
        parent.sortKey = "name" -- Default sort by name
        parent.sortAscending = true
    end
    
    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\Achievement_Character_Human_Female")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    titleText:SetText("|cffa335eeYour Characters|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText(#characters .. " characters tracked")
    
    yOffset = yOffset + 75 -- Reduced spacing
    
    -- ===== TOTAL GOLD DISPLAY =====
    local totalGold = 0
    for _, char in ipairs(characters) do
        totalGold = totalGold + (char.gold or 0)
    end
    
    local goldCard = CreateCard(parent, 50)
    goldCard:SetPoint("TOPLEFT", 10, -yOffset)
    goldCard:SetPoint("TOPRIGHT", -10, -yOffset)
    goldCard:SetBackdropColor(0.12, 0.10, 0.05, 1)
    goldCard:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    local goldIcon = goldCard:CreateTexture(nil, "ARTWORK")
    goldIcon:SetSize(28, 28)
    goldIcon:SetPoint("LEFT", 15, 0)
    goldIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    
    local goldLabel = goldCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goldLabel:SetPoint("LEFT", goldIcon, "RIGHT", 10, 0)
    goldLabel:SetText("Total Gold: |cffffd700" .. FormatGold(totalGold) .. "|r")
    
    yOffset = yOffset + 55 -- Reduced spacing
    
    -- ===== SORTABLE TABLE HEADER =====
    local columns = {
        {key = "name", label = "CHARACTER", align = "LEFT", offset = 15, width = 200},
        {key = "level", label = "LEVEL", align = "LEFT", offset = 220, width = 100},
        {key = "gold", label = "GOLD", align = "RIGHT", offset = -140, width = 120},
        {key = "lastSeen", label = "LAST SEEN", align = "RIGHT", offset = -15, width = 120}
    }
    
    local header, getCurrentSort = CreateSortableTableHeader(
        parent,
        columns,
        width,
        function(sortKey, isAscending)
            -- Save sort state
            parent.sortKey = sortKey
            parent.sortAscending = isAscending
            -- Refresh to re-sort
            self:RefreshUI()
        end,
        parent.sortKey,
        parent.sortAscending
    )
    
    header:SetPoint("TOPLEFT", 10, -yOffset)
    yOffset = yOffset + 32
    
    -- ===== SORT CHARACTERS =====
    table.sort(characters, function(a, b)
        local key = parent.sortKey
        local asc = parent.sortAscending
        
        local valA, valB
        
        if key == "name" then
            valA = (a.name or ""):lower()
            valB = (b.name or ""):lower()
        elseif key == "level" then
            valA = a.level or 0
            valB = b.level or 0
        elseif key == "gold" then
            valA = a.gold or 0
            valB = b.gold or 0
        elseif key == "lastSeen" then
            valA = a.lastSeen or 0
            valB = b.lastSeen or 0
        else
            return false
        end
        
        if asc then
            return valA < valB
        else
            return valA > valB
        end
    end)
    
    -- ===== EMPTY STATE =====
    if #characters == 0 then
        local emptyIcon = parent:CreateTexture(nil, "ARTWORK")
        emptyIcon:SetSize(48, 48)
        emptyIcon:SetPoint("TOP", 0, -yOffset - 30)
        emptyIcon:SetTexture("Interface\\Icons\\Ability_Spy")
        emptyIcon:SetDesaturated(true)
        emptyIcon:SetAlpha(0.4)
        
        local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        emptyText:SetPoint("TOP", 0, -yOffset - 90)
        emptyText:SetText("|cff666666No characters tracked yet|r")
        
        local emptyDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyDesc:SetPoint("TOP", 0, -yOffset - 115)
        emptyDesc:SetTextColor(0.5, 0.5, 0.5)
        emptyDesc:SetText("Characters are automatically registered on login")
        
        return yOffset + 200
    end
    
    -- ===== CHARACTER ROWS =====
    for i, char in ipairs(characters) do
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(width, 36)
        row:SetPoint("TOPLEFT", 10, -yOffset)
        row:EnableMouse(true)
        
        -- Row background (alternating colors)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local bgColor = i % 2 == 0 and {0.08, 0.08, 0.10, 1} or {0.05, 0.05, 0.06, 1}
        bg:SetColorTexture(unpack(bgColor))
        row.bgColor = bgColor
        
        -- Class color
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        
        -- Class icon
        local classIcon = row:CreateTexture(nil, "ARTWORK")
        classIcon:SetSize(24, 24)
        classIcon:SetPoint("LEFT", 12, 0)
        local coords = CLASS_ICON_TCOORDS[char.classFile]
        if coords then
            classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            classIcon:SetTexCoord(unpack(coords))
        else
            classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        
        -- Character name (in class color)
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 44, 0)
        nameText:SetWidth(145)
        nameText:SetJustifyH("LEFT")
        nameText:SetText(string.format("|cff%02x%02x%02x%s|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.name or "Unknown"))
        
        -- Level (in class color, aligned with header)
        local levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        levelText:SetPoint("LEFT", 220, 0)
        levelText:SetText(string.format("|cff%02x%02x%02x%d|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.level or 1))
        
        -- Gold (aligned with header)
        local goldText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        goldText:SetPoint("RIGHT", -140, 0)
        goldText:SetJustifyH("RIGHT")
        goldText:SetText("|cffffd700" .. FormatGold(char.gold or 0) .. "|r")
        
        -- Last seen (aligned with header)
        local lastSeenText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lastSeenText:SetPoint("RIGHT", -15, 0)
        lastSeenText:SetJustifyH("RIGHT")
        lastSeenText:SetTextColor(0.5, 0.5, 0.5)
        if char.lastSeen then
            local timeDiff = time() - char.lastSeen
            if timeDiff < 60 then
                lastSeenText:SetText("Just now")
            elseif timeDiff < 3600 then
                lastSeenText:SetText(math.floor(timeDiff / 60) .. "m ago")
            elseif timeDiff < 86400 then
                lastSeenText:SetText(math.floor(timeDiff / 3600) .. "h ago")
            else
                lastSeenText:SetText(math.floor(timeDiff / 86400) .. "d ago")
            end
        else
            lastSeenText:SetText("Unknown")
        end
        
        -- Hover effect + Tooltip
        row:SetScript("OnEnter", function(self)
            bg:SetColorTexture(0.18, 0.18, 0.25, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(char.name or "Unknown", classColor.r, classColor.g, classColor.b)
            GameTooltip:AddLine(char.realm or "", 0.5, 0.5, 0.5)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Class:", char.class or "Unknown", 1, 1, 1, classColor.r, classColor.g, classColor.b)
            GameTooltip:AddDoubleLine("Level:", tostring(char.level or 1), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Gold:", FormatGold(char.gold or 0), 1, 1, 1, 1, 0.82, 0)
            if char.faction then
                GameTooltip:AddDoubleLine("Faction:", char.faction, 1, 1, 1, 0.7, 0.7, 0.7)
            end
            if char.race then
                GameTooltip:AddDoubleLine("Race:", char.race, 1, 1, 1, 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        
        row:SetScript("OnLeave", function(self)
            bg:SetColorTexture(unpack(self.bgColor))
            GameTooltip:Hide()
        end)
        
        yOffset = yOffset + 38
    end
    
    return yOffset + 20
end
