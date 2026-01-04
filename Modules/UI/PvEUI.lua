--[[
    Warband Nexus - PvE Progress Tab
    Display Great Vault, Mythic+ keystones, and Raid lockouts for all characters
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local function GetCOLORS()
    return ns.UI_COLORS
end

-- Performance: Local function references
local format = string.format
local date = date

-- Expand/Collapse State Management
local expandedStates = {}

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
-- GREAT VAULT HELPER FUNCTIONS
--============================================================================

--[[
    Determine if a vault activity slot is at maximum completion level
    @param activity table - Activity data from Great Vault
    @param typeName string - Activity type name ("Raid", "M+", "World", "PvP")
    @return boolean - True if at maximum level, false otherwise
]]
local function IsVaultSlotAtMax(activity, typeName)
    if not activity or not activity.level then
        return false
    end
    
    local level = activity.level
    
    -- Define max thresholds per activity type
    if typeName == "Raid" then
        -- For raids, level typically represents difficulty tier
        -- Max is usually Mythic (highest difficulty) with 8/8 bosses
        -- In current implementation, checking if completed at highest available tier
        return level >= 8 -- Mythic raid completion
    elseif typeName == "M+" then
        -- For M+, level is the keystone level
        -- Consider 10+ as "max" for meaningful vault upgrades
        return level >= 10
    elseif typeName == "World" or typeName == "PvP" then
        -- For World/PvP, we consider completed slots at reasonable thresholds
        -- These typically have lower variance, so completed = max
        return true
    end
    
    return false
end

--[[
    Get reward item level from activity data or calculate fallback
    @param activity table - Activity data from Great Vault
    @return number|nil - Item level or nil if unavailable
]]
local function GetRewardItemLevel(activity)
    if not activity then
        return nil
    end
    
    -- Use stored reward item level if available
    if activity.rewardItemLevel and activity.rewardItemLevel > 0 then
        return activity.rewardItemLevel
    end
    
    return nil
end

--[[
    Get display text for vault activity completion
    @param activity table - Activity data
    @param typeName string - Activity type name
    @return string - Display text for the activity (e.g., "Heroic", "+7", "Tier 1")
]]
local function GetVaultActivityDisplayText(activity, typeName)
    if not activity then
        return "Unknown"
    end
    
    if typeName == "Raid" then
        local difficulty = "Unknown"
        if activity.level then
            -- Raid level corresponds to difficulty ID
            if activity.level >= 16 then
                difficulty = "Mythic"
            elseif activity.level >= 15 then
                difficulty = "Heroic"
            elseif activity.level >= 14 then
                difficulty = "Normal"
            else
                difficulty = "LFR"
            end
        end
        return difficulty
    elseif typeName == "M+" then
        local level = activity.level or 0
        return format("+%d", level)
    elseif typeName == "World" then
        local tier = activity.level or 1
        return format("Tier %d", tier)
    elseif typeName == "PvP" then
        return "PvP"
    end
    
    return typeName
end

--============================================================================
-- DRAW PVE PROGRESS (Great Vault, Lockouts, M+)
--============================================================================

function WarbandNexus:DrawPvEProgress(parent)
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    
    -- Get current player key
    local currentPlayerName = UnitName("player")
    local currentPlayerRealm = GetRealmName()
    local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
    
    -- Load sorting preferences from profile (persistent across sessions)
    if not parent.sortPrefsLoaded then
        parent.sortKey = self.db.profile.pveSort.key
        parent.sortAscending = self.db.profile.pveSort.ascending
        parent.sortPrefsLoaded = true
    end
    
    -- ===== SORT CHARACTERS WITH FAVORITES ALWAYS ON TOP =====
    -- Use the same sorting logic as Characters tab
    local currentChar = nil
    local favorites = {}
    local regular = {}
    
    for _, char in ipairs(characters) do
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        
        -- Separate current character
        if charKey == currentPlayerKey then
            currentChar = char
        elseif self:IsFavoriteCharacter(charKey) then
            table.insert(favorites, char)
        else
            table.insert(regular, char)
        end
    end
    
    -- Sort function (with custom order support, same as Characters tab)
    local function sortCharacters(list, orderKey)
        local customOrder = self.db.profile.characterOrder and self.db.profile.characterOrder[orderKey] or {}
        
        -- If custom order exists and has items, use it
        if #customOrder > 0 then
            local ordered = {}
            local charMap = {}
            
            -- Create a map for quick lookup
            for _, char in ipairs(list) do
                local key = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
                charMap[key] = char
            end
            
            -- Add characters in custom order
            for _, charKey in ipairs(customOrder) do
                if charMap[charKey] then
                    table.insert(ordered, charMap[charKey])
                    charMap[charKey] = nil  -- Remove to track remaining
                end
            end
            
            -- Add any new characters not in custom order (at the end, sorted)
            local remaining = {}
            for _, char in pairs(charMap) do
                table.insert(remaining, char)
            end
            table.sort(remaining, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
            end)
            for _, char in ipairs(remaining) do
                table.insert(ordered, char)
            end
            
            return ordered
        else
            -- Default sort: level desc → name asc
            table.sort(list, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
            end)
            return list
        end
    end
    
    -- Sort both groups with custom order
    favorites = sortCharacters(favorites, "favorites")
    regular = sortCharacters(regular, "regular")
    
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
    titleIcon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "PvE Progress|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Great Vault, Raid Lockouts & Mythic+ across your Warband")
    
    -- Weekly reset timer
    local resetText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resetText:SetPoint("RIGHT", -15, 0)
    resetText:SetTextColor(0.3, 0.9, 0.3) -- Green color
    
    -- Calculate time until weekly reset
    local function GetWeeklyResetTime()
        local serverTime = GetServerTime()
        local resetTime
        
        -- Try C_DateAndTime first (modern API)
        if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
            local secondsUntil = C_DateAndTime.GetSecondsUntilWeeklyReset()
            if secondsUntil then
                return secondsUntil
            end
        end
        
        -- Fallback: Calculate manually (US reset = Tuesday 15:00 UTC, EU = Wednesday 07:00 UTC)
        local region = GetCVar("portal")
        local resetDay = (region == "EU") and 3 or 2 -- 2=Tuesday, 3=Wednesday
        local resetHour = (region == "EU") and 7 or 15
        
        local currentDate = date("*t", serverTime)
        local currentWeekday = currentDate.wday -- 1=Sunday, 2=Monday, etc.
        
        -- Days until next reset
        local daysUntil = (resetDay - currentWeekday + 7) % 7
        if daysUntil == 0 and currentDate.hour >= resetHour then
            daysUntil = 7
        end
        
        -- Calculate exact reset time
        local nextReset = serverTime + (daysUntil * 86400)
        local nextResetDate = date("*t", nextReset)
        nextResetDate.hour = resetHour
        nextResetDate.min = 0
        nextResetDate.sec = 0
        
        resetTime = time(nextResetDate)
        return resetTime - serverTime
    end
    
    local function FormatResetTime(seconds)
        if not seconds or seconds <= 0 then
            return "Soon"
        end
        
        local days = math.floor(seconds / 86400)
        local hours = math.floor((seconds % 86400) / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        
        if days > 0 then
            return string.format("%d Days %d Hours", days, hours)
        elseif hours > 0 then
            return string.format("%d Hours %d Minutes", hours, mins)
        else
            return string.format("%d Minutes", mins)
        end
    end
    
    -- Update timer
    local secondsUntil = GetWeeklyResetTime()
    resetText:SetText(FormatResetTime(secondsUntil))
    
    -- Refresh every minute
    titleCard:SetScript("OnUpdate", function(self, elapsed)
        self.timeSinceUpdate = (self.timeSinceUpdate or 0) + elapsed
        if self.timeSinceUpdate >= 60 then
            self.timeSinceUpdate = 0
            local seconds = GetWeeklyResetTime()
            resetText:SetText(FormatResetTime(seconds))
        end
    end)
    
    yOffset = yOffset + 75 -- Reduced spacing
    
    -- ===== EMPTY STATE =====
    if #characters == 0 then
        local emptyIcon = parent:CreateTexture(nil, "ARTWORK")
        emptyIcon:SetSize(64, 64)
        emptyIcon:SetPoint("TOP", 0, -yOffset - 50)
        emptyIcon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")
        emptyIcon:SetDesaturated(true)
        emptyIcon:SetAlpha(0.4)
        
        local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        emptyText:SetPoint("TOP", 0, -yOffset - 130)
        emptyText:SetText("|cff666666No Characters Found|r")
        
        local emptyDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyDesc:SetPoint("TOP", 0, -yOffset - 160)
        emptyDesc:SetTextColor(0.6, 0.6, 0.6)
        emptyDesc:SetText("Log in to any character to start tracking PvE progress")
        
        local emptyHint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        emptyHint:SetPoint("TOP", 0, -yOffset - 185)
        emptyHint:SetTextColor(0.5, 0.5, 0.5)
        emptyHint:SetText("Great Vault, Mythic+ and Raid Lockouts will be displayed here")
        
        return yOffset + 240
    end
    
    -- ===== CHARACTER COLLAPSIBLE HEADERS (Favorites first, then regular) =====
    for i, char in ipairs(characters) do
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        local isFavorite = self:IsFavoriteCharacter(charKey)
        local pve = char.pve or {}
        
        -- Smart expand: expand if current character or has unclaimed vault rewards
        local charExpandKey = "pve-char-" .. charKey
        local isCurrentChar = (charKey == currentPlayerKey)
        local hasVaultReward = pve.hasUnclaimedRewards or false
        local charExpanded = IsExpanded(charExpandKey, isCurrentChar or hasVaultReward)
        
        -- Create collapsible header
        local charHeader, charBtn = CreateCollapsibleHeader(
            parent,
            "", -- Empty text, we'll add it manually
            charExpandKey,
            charExpanded,
            function(isExpanded) ToggleExpand(charExpandKey, isExpanded) end
        )
        charHeader:SetPoint("TOPLEFT", 10, -yOffset)
        charHeader:SetPoint("TOPRIGHT", -10, -yOffset)
        
        yOffset = yOffset + 35
        
        -- Favorite button (left side, next to collapse button)
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
                btn.icon:SetTexture("Interface\\COMMON\\FavoritesIcon")
                btn.icon:SetDesaturated(false)
                btn.icon:SetVertexColor(1, 0.84, 0)
            else
                btn.icon:SetTexture("Interface\\COMMON\\FavoritesIcon")
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
        
        -- Character name text (after favorite button, class colored)
        local charNameText = charHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        charNameText:SetPoint("LEFT", favButton, "RIGHT", 6, 0)
        charNameText:SetText(string.format("|cff%02x%02x%02x%s|r |cff888888Lv %d|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.name, char.level or 1))
        
        -- Vault badge (right side of header)
        if hasVaultReward then
            local vaultContainer = CreateFrame("Frame", nil, charHeader)
            vaultContainer:SetSize(110, 20)
            vaultContainer:SetPoint("RIGHT", -10, 0)
            
            local vaultIcon = vaultContainer:CreateTexture(nil, "ARTWORK")
            vaultIcon:SetSize(16, 16)
            vaultIcon:SetPoint("LEFT", 0, 0)
            vaultIcon:SetTexture("Interface\\Icons\\achievement_guildperk_bountifulbags")
            
            local vaultText = vaultContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            vaultText:SetPoint("LEFT", vaultIcon, "RIGHT", 4, 0)
            vaultText:SetText("Great Vault")
            vaultText:SetTextColor(0.9, 0.9, 0.9)
            
            local checkmark = vaultContainer:CreateTexture(nil, "OVERLAY")
            checkmark:SetSize(14, 14)
            checkmark:SetPoint("LEFT", vaultText, "RIGHT", 4, 0)
            checkmark:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
        end
        
        -- 3 Cards (only when expanded)
        if charExpanded then
            local cardContainer = CreateFrame("Frame", nil, parent)
            cardContainer:SetPoint("TOPLEFT", 10, -yOffset)
            cardContainer:SetPoint("TOPRIGHT", -10, -yOffset)
            
            local totalWidth = parent:GetWidth() - 20
            local card1Width = totalWidth * 0.30
            local card2Width = totalWidth * 0.35
            local card3Width = totalWidth * 0.35
            local cardHeight = 200  -- Reduced from 280 to 200
            local cardSpacing = 5
            
            -- === CARD 1: GREAT VAULT (30%) ===
            local vaultCard = CreateCard(cardContainer, cardHeight)
            vaultCard:SetPoint("TOPLEFT", 0, 0)
            vaultCard:SetWidth(card1Width - cardSpacing)
            
            -- Helper function to get WoW icon textures for vault activity types
            local function GetVaultTypeIcon(typeName)
                local icons = {
                    ["Raid"] = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
                    ["M+"] = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
                    ["World"] = "Interface\\Icons\\INV_Misc_Map_01"
                }
                return icons[typeName] or "Interface\\Icons\\INV_Misc_QuestionMark"
            end
            
            local vaultY = 15  -- Start padding
        
        if pve.greatVault and #pve.greatVault > 0 then
            local vaultByType = {}
            for _, activity in ipairs(pve.greatVault) do
                local typeName = "Unknown"
                local typeNum = activity.type
                
                if Enum and Enum.WeeklyRewardChestThresholdType then
                    if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then typeName = "Raid"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then typeName = "M+"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then typeName = "PvP"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then typeName = "World"
                    end
                else
                    -- Fallback numeric values based on API:
                    -- 1 = Activities (M+), 2 = RankedPvP, 3 = Raid, 6 = World
                    if typeNum == 3 then typeName = "Raid"
                    elseif typeNum == 1 then typeName = "M+"
                    elseif typeNum == 2 then typeName = "PvP"
                    elseif typeNum == 6 then typeName = "World"
                    end
                end
                
                if not vaultByType[typeName] then vaultByType[typeName] = {} end
                table.insert(vaultByType[typeName], activity)
            end
            
            -- Column Layout Constants
            local cardWidth = card1Width - cardSpacing
            local typeColumnWidth = 70  -- Icon + label width
            local slotsAreaWidth = cardWidth - typeColumnWidth - 30  -- 30px for padding
            local slotWidth = slotsAreaWidth / 3  -- Three slots evenly distributed
            
            -- Calculate available space for rows (no header row)
            local cardContentHeight = cardHeight - vaultY - 10  -- 10px bottom padding
            local numTypes = 3  -- Raid, M+, World (PvP removed)
            local rowHeight = math.floor(cardContentHeight / numTypes)
            
            -- Default thresholds for each activity type (when no data exists)
            local defaultThresholds = {
                ["Raid"] = {2, 4, 6},
                ["M+"] = {1, 4, 8},
                ["World"] = {3, 3, 3},
                ["PvP"] = {3, 3, 3}
            }
            
            -- Table Rows (3 TYPES - evenly distributed)
            local sortedTypes = {"Raid", "M+", "World"}
            local rowIndex = 0
            for _, typeName in ipairs(sortedTypes) do
                local activities = vaultByType[typeName]
                
                -- Create row frame container for better positioning
                local rowFrame = CreateFrame("Frame", nil, vaultCard)
                rowFrame:SetPoint("TOPLEFT", 10, -vaultY)
                rowFrame:SetPoint("TOPRIGHT", -10, -vaultY)
                rowFrame:SetHeight(rowHeight - 2)
                
                -- Row background (alternating colors)
                local rowBg = rowFrame:CreateTexture(nil, "BACKGROUND")
                rowBg:SetAllPoints()
                if rowIndex % 2 == 0 then
                    rowBg:SetColorTexture(0.1, 0.1, 0.12, 0.5)
                else
                    rowBg:SetColorTexture(0.08, 0.08, 0.1, 0.5)
                end
                
                -- Icon texture (left side)
                local iconTexture = rowFrame:CreateTexture(nil, "ARTWORK")
                iconTexture:SetSize(16, 16)
                iconTexture:SetPoint("LEFT", 5, 0)
                iconTexture:SetTexture(GetVaultTypeIcon(typeName))
                
                -- Type label (next to icon)
                local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                label:SetPoint("LEFT", 25, 0)  -- 5px offset + 16px icon + 4px padding
                label:SetText(string.format("|cffffffff%s|r", typeName))
                
                -- Create individual slot frames for proper alignment
                local thresholds = defaultThresholds[typeName] or {3, 3, 3}
                
                for slotIndex = 1, 3 do
                    -- Create slot container frame
                    local slotFrame = CreateFrame("Frame", nil, rowFrame)
                    local xOffset = typeColumnWidth + ((slotIndex - 1) * slotWidth)
                    slotFrame:SetSize(slotWidth, rowHeight - 2)
                    slotFrame:SetPoint("LEFT", rowFrame, "LEFT", xOffset, 0)
                    
                    -- Get activity data for this slot
                    local activity = activities and activities[slotIndex]
                    local threshold = (activity and activity.threshold) or thresholds[slotIndex] or 0
                    local progress = activity and activity.progress or 0
                    local isComplete = (threshold > 0 and progress >= threshold)
                    
                    if activity and isComplete then
                        -- COMPLETED SLOT: Show 3 lines (all centered)
                        -- Line 1: Green Tick (centered at top)
                        local checkIcon = slotFrame:CreateTexture(nil, "OVERLAY")
                        checkIcon:SetSize(16, 16)
                        checkIcon:SetPoint("TOP", slotFrame, "TOP", 0, -8)
                        checkIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                        
                        -- Line 2: Tier/Difficulty/Keystone Level (centered)
                        local displayText = GetVaultActivityDisplayText(activity, typeName)
                        local tierText = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        tierText:SetPoint("TOP", checkIcon, "BOTTOM", 0, -4)
                        tierText:SetText(string.format("|cff00ff00%s|r", displayText))
                        
                        -- Line 3: Reward iLvL (centered)
                        local rewardIlvl = GetRewardItemLevel(activity)
                        if rewardIlvl and rewardIlvl > 0 then
                            local ilvlText = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            ilvlText:SetPoint("TOP", tierText, "BOTTOM", 0, -2)
                            ilvlText:SetText(string.format("|cffffd700iLvL %d|r", rewardIlvl))
                            
                            -- Add upgrade arrow next to iLvL if not at max
                            local isAtMax = IsVaultSlotAtMax(activity, typeName)
                            if not isAtMax then
                                local arrowTexture = slotFrame:CreateTexture(nil, "OVERLAY")
                                arrowTexture:SetSize(12, 12)
                                arrowTexture:SetPoint("LEFT", ilvlText, "RIGHT", 2, 0)
                                
                                -- Use SetAtlas for the loottoast-arrow-green atlas
                                if arrowTexture.SetAtlas then
                                    arrowTexture:SetAtlas("loottoast-arrow-green")
                                else
                                    arrowTexture:SetTexture("Interface\\BUTTONS\\UI-MicroStream-Green")
                                end
                            end
                        end
                        
                    elseif activity and not isComplete then
                        -- Incomplete: Show progress numbers (centered)
                        local progressText = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        progressText:SetPoint("CENTER", 0, 0)
                        progressText:SetText(string.format("|cffffcc00%d|r|cffffffff/|r|cffffcc00%d|r", 
                            progress, threshold))
                    else
                        -- No data: Show empty with threshold (centered)
                        local emptyText = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        emptyText:SetPoint("CENTER", 0, 0)
                        if threshold > 0 then
                            emptyText:SetText(string.format("|cff888888%d|r|cff666666/|r|cff888888%d|r", 0, threshold))
                        else
                            emptyText:SetText("|cff666666-|r")
                        end
                    end
                end
                
                vaultY = vaultY + rowHeight
                rowIndex = rowIndex + 1
            end
        else
                local noVault = vaultCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noVault:SetPoint("CENTER", vaultCard, "CENTER", 0, 0)
            noVault:SetText("|cff666666No vault data|r")
            end
            
            -- === CARD 2: M+ DUNGEONS (35%) ===
            local mplusCard = CreateCard(cardContainer, cardHeight)
            mplusCard:SetPoint("TOPLEFT", card1Width, 0)
            mplusCard:SetWidth(card2Width - cardSpacing)
            
            local mplusY = 15
            
            -- Overall Score (larger, at top)
            local totalScore = pve.mythicPlus.overallScore or 0
            local scoreText = mplusCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            scoreText:SetPoint("TOP", mplusCard, "TOP", 0, -mplusY)
            scoreText:SetText(string.format("|cffffd700Overall Score: %d|r", totalScore))
            mplusY = mplusY + 35  -- Space before grid
            
            if pve.mythicPlus.dungeons and #pve.mythicPlus.dungeons > 0 then
                local iconsPerRow = 4
                local iconSize = 42  -- Increased from 35 to 42
                local iconSpacing = 12  -- Increased from 8 to 12 for better distribution
                local totalDungeons = #pve.mythicPlus.dungeons
                
                -- Calculate grid dimensions
                local gridWidth = (iconsPerRow * iconSize) + ((iconsPerRow - 1) * iconSpacing)
                local cardWidth = card2Width - cardSpacing
                local startX = (cardWidth - gridWidth) / 2  -- Center the grid
                local gridY = mplusY
                
                for i, dungeon in ipairs(pve.mythicPlus.dungeons) do
                    local col = (i - 1) % iconsPerRow
                    local row = math.floor((i - 1) / iconsPerRow)
                    
                    local iconX = startX + (col * (iconSize + iconSpacing))
                    local iconY = gridY + (row * (iconSize + iconSpacing + 22))  -- Adjusted for larger icons
                    
                    local iconFrame = CreateFrame("Frame", nil, mplusCard)
                    iconFrame:SetSize(iconSize, iconSize)
                    iconFrame:SetPoint("TOPLEFT", iconX, -iconY)
                    iconFrame:EnableMouse(true)
                    
                    local texture = iconFrame:CreateTexture(nil, "ARTWORK")
                    texture:SetAllPoints()
                    if dungeon.texture then
                        texture:SetTexture(dungeon.texture)
                    else
                        texture:SetColorTexture(0.2, 0.2, 0.2, 1)
                    end
                    
                    if dungeon.bestLevel and dungeon.bestLevel > 0 then
                        -- Darken background overlay for better contrast
                        local overlay = iconFrame:CreateTexture(nil, "BORDER")
                        overlay:SetAllPoints()
                        overlay:SetColorTexture(0, 0, 0, 0.4)  -- Semi-transparent black
                        
                        -- Key level INSIDE icon (centered, larger) - using GameFont
                        local levelText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
                        levelText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)  -- Centered in icon
                        levelText:SetText(string.format("|cffffcc00+%d|r", dungeon.bestLevel))  -- Gold/yellow
                        
                        -- Score BELOW icon - using GameFont
                        local dungeonScore = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                        dungeonScore:SetPoint("TOP", iconFrame, "BOTTOM", 0, -3)
                        dungeonScore:SetText(string.format("|cffffffff%d|r", dungeon.score or 0))
                    else
                        -- Gray overlay for incomplete
                        local overlay = iconFrame:CreateTexture(nil, "BORDER")
                        overlay:SetAllPoints()
                        overlay:SetColorTexture(0, 0, 0, 0.6)  -- Darker for incomplete
                        
                        -- "Not Done" text inside icon - using GameFont
                        local notDone = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
                        notDone:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        notDone:SetText("|cff888888?|r")  -- Question mark instead of dash
                        
                        -- Dash below - using GameFont
                        local zeroScore = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                        zeroScore:SetPoint("TOP", iconFrame, "BOTTOM", 0, -3)
                        zeroScore:SetText("|cff666666-|r")
                    end
                    
                    iconFrame:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(dungeon.name or "Unknown", 1, 1, 1)
                        if dungeon.bestLevel and dungeon.bestLevel > 0 then
                            GameTooltip:AddLine(string.format("Best: |cffff8000+%d|r", dungeon.bestLevel), 1, 0.5, 0)
                            GameTooltip:AddLine(string.format("Score: |cffffffff%d|r", dungeon.score or 0), 1, 1, 1)
                        else
                            GameTooltip:AddLine("|cff666666Not completed|r", 0.6, 0.6, 0.6)
                        end
                        GameTooltip:Show()
                    end)
                    iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
            else
                local noData = mplusCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noData:SetPoint("TOPLEFT", 15, -mplusY)
                noData:SetText("|cff666666No data|r")
            end
            
            -- === CARD 3: RAID LOCKOUTS (35%) ===
            local lockoutCard = CreateCard(cardContainer, cardHeight)
            lockoutCard:SetPoint("TOPLEFT", card1Width + card2Width, 0)
            lockoutCard:SetWidth(card3Width)
            
            -- Work in Progress message
            local wipText = lockoutCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            wipText:SetPoint("CENTER", lockoutCard, "CENTER", 0, 0)
            wipText:SetText("|cffffcc00Work in Progress|r")
            
            cardContainer:SetHeight(cardHeight)
            yOffset = yOffset + cardHeight + 10
        end
        
        yOffset = yOffset + 5
    end
    
    return yOffset + 20
end

