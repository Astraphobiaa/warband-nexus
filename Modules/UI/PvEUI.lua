--[[
    Warband Nexus - PvE Progress Tab
    Display Great Vault, Mythic+ keystones, and Raid lockouts for all characters
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard

-- Performance: Local function references
local format = string.format
local date = date

--============================================================================
-- DRAW PVE PROGRESS (Great Vault, Lockouts, M+)
--============================================================================

function WarbandNexus:DrawPvEProgress(parent)
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    
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
    titleText:SetText("|cffa335eePvE Progress|r")
    
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
            return string.format("%dd %dh", days, hours)
        elseif hours > 0 then
            return string.format("%dh %dm", hours, mins)
        else
            return string.format("%dm", mins)
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
    
    -- ===== CHARACTER CARDS =====
    for i, char in ipairs(characters) do
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        
        -- Character card
        local charCard = CreateCard(parent, 0) -- Height will be set dynamically
        charCard:SetPoint("TOPLEFT", 10, -yOffset)
        charCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local cardYOffset = 12
        
        -- Character header
        local charHeader = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        charHeader:SetPoint("TOPLEFT", 15, -cardYOffset)
        charHeader:SetText(string.format("|cff%02x%02x%02x%s|r |cff888888Lv %d|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.name, char.level or 1))
        
        -- Last updated time
        local lastSeen = char.lastSeen or 0
        local lastSeenText = ""
        if lastSeen > 0 then
            local diff = time() - lastSeen
            if diff < 60 then
                lastSeenText = "Updated: Just now"
            elseif diff < 3600 then
                lastSeenText = string.format("Updated: %dm ago", math.floor(diff / 60))
            elseif diff < 86400 then
                lastSeenText = string.format("Updated: %dh ago", math.floor(diff / 3600))
            else
                lastSeenText = string.format("Updated: %dd ago", math.floor(diff / 86400))
            end
        else
            lastSeenText = "Never updated"
        end
        
        local lastSeenLabel = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lastSeenLabel:SetPoint("TOPRIGHT", -15, -cardYOffset)
        lastSeenLabel:SetText("|cff888888" .. lastSeenText .. "|r")
        
        cardYOffset = cardYOffset + 25
        
        local pve = char.pve or {}
        
        -- Create three-column layout for symmetrical display
        local columnWidth = (width - 60) / 3  -- 3 equal columns with spacing
        local columnStartY = cardYOffset
        
        -- === COLUMN 1: GREAT VAULT ===
        local vaultX = 15
        local vaultY = columnStartY
        
        local vaultTitle = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        vaultTitle:SetPoint("TOPLEFT", vaultX, -vaultY)
        vaultTitle:SetText("|cffffd700Great Vault|r")
        vaultY = vaultY + 22  -- Increased spacing after title
        
        if pve.greatVault and #pve.greatVault > 0 then
            -- Group by type using Enum values
            local vaultByType = {}
            for _, activity in ipairs(pve.greatVault) do
                local typeName = "Unknown"
                local typeNum = activity.type
                
                -- Try Enum first if available, fallback to numeric comparison
                if Enum and Enum.WeeklyRewardChestThresholdType then
                    if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then
                        typeName = "Raid"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then
                        typeName = "M+"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then
                        typeName = "PvP"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then
                        typeName = "World"
                    end
                else
                    -- Fallback: numeric comparison
                    -- Based on C_WeeklyRewards.ActivityType
                    if typeNum == 1 then typeName = "Raid"
                    elseif typeNum == 2 then typeName = "M+"
                    elseif typeNum == 3 then typeName = "PvP"
                    elseif typeNum == 4 then typeName = "World"
                    end
                end
                
                if not vaultByType[typeName] then vaultByType[typeName] = {} end
                table.insert(vaultByType[typeName], activity)
            end
            
            -- Display in order: Raid, M+, World, PvP
            local sortedTypes = {"Raid", "M+", "World", "PvP"}
            for _, typeName in ipairs(sortedTypes) do
                local activities = vaultByType[typeName]
                if activities then
                    -- Create label (fixed width for alignment)
                    local label = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    label:SetPoint("TOPLEFT", vaultX + 10, -vaultY)
                    label:SetWidth(50) -- Fixed width for type name
                    label:SetText(typeName .. ":")
                    label:SetTextColor(0.85, 0.85, 0.85)
                    label:SetJustifyH("LEFT")
                    label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
                    
                    -- Create progress display (aligned to the right of label)
                    local progressLine = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    progressLine:SetPoint("TOPLEFT", vaultX + 60, -vaultY)
                    progressLine:SetWidth(columnWidth - 65)
                    
                    local progressParts = {}
                    for _, a in ipairs(activities) do
                        -- Cap progress at threshold (don't show 3/2, show 2/2)
                        local progress = a.progress or 0
                        local threshold = a.threshold or 0
                        if progress > threshold and threshold > 0 then
                            progress = threshold
                        end
                        
                        local pct = threshold > 0 and (progress / threshold * 100) or 0
                        local color = pct >= 100 and "|cff00ff00" or "|cffffcc00"
                        table.insert(progressParts, string.format("%s%d/%d|r", color, progress, threshold))
                    end
                    progressLine:SetText(table.concat(progressParts, " "))
                    progressLine:SetTextColor(0.85, 0.85, 0.85)
                    progressLine:SetJustifyH("LEFT")
                    progressLine:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
                    vaultY = vaultY + 17  -- Slightly more spacing between lines
                end
            end
        else
            local noVault = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noVault:SetPoint("TOPLEFT", vaultX + 10, -vaultY)
            noVault:SetText("|cff666666No data|r")
            noVault:SetTextColor(0.5, 0.5, 0.5)
            vaultY = vaultY + 15
        end
        
        -- === COLUMN 2: MYTHIC+ ===
        local mplusX = 15 + columnWidth
        local mplusY = columnStartY
        
        local mplusTitle = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mplusTitle:SetPoint("TOPLEFT", mplusX, -mplusY)
        mplusTitle:SetText("|cffa335eeM+ Keystone|r")
        mplusY = mplusY + 22  -- Increased spacing after title
        
        if pve.mythicPlus and (pve.mythicPlus.keystone or pve.mythicPlus.weeklyBest or pve.mythicPlus.runsThisWeek) then
            -- Current keystone
            if pve.mythicPlus.keystone then
                local keystoneInfo = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                keystoneInfo:SetPoint("TOPLEFT", mplusX + 10, -mplusY)
                keystoneInfo:SetWidth(columnWidth - 20)
                keystoneInfo:SetText(string.format("|cffff8000%s +%d|r", 
                    pve.mythicPlus.keystone.name or "Unknown", 
                    pve.mythicPlus.keystone.level or 0))
                keystoneInfo:SetJustifyH("LEFT")
                mplusY = mplusY + 15
            end
            
            -- Weekly stats
            if pve.mythicPlus.weeklyBest and pve.mythicPlus.weeklyBest > 0 then
                local bestLine = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                bestLine:SetPoint("TOPLEFT", mplusX + 10, -mplusY)
                bestLine:SetText(string.format("Best: |cff00ff00+%d|r", pve.mythicPlus.weeklyBest))
                bestLine:SetTextColor(0.8, 0.8, 0.8)
                mplusY = mplusY + 15
            end
            
            if pve.mythicPlus.runsThisWeek and pve.mythicPlus.runsThisWeek > 0 then
                local runsLine = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                runsLine:SetPoint("TOPLEFT", mplusX + 10, -mplusY)
                runsLine:SetText(string.format("Runs: |cffa335ee%d|r", pve.mythicPlus.runsThisWeek))
                runsLine:SetTextColor(0.8, 0.8, 0.8)
                mplusY = mplusY + 15
            end
        else
            local noMplus = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noMplus:SetPoint("TOPLEFT", mplusX + 10, -mplusY)
            noMplus:SetText("|cff666666No keystone|r")
            noMplus:SetTextColor(0.5, 0.5, 0.5)
            mplusY = mplusY + 15
        end
        
        -- === COLUMN 3: RAID LOCKOUTS ===
        local lockoutX = 15 + (columnWidth * 2)
        local lockoutY = columnStartY
        
        local lockoutTitle = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockoutTitle:SetPoint("TOPLEFT", lockoutX, -lockoutY)
        lockoutTitle:SetText("|cff0070ddRaid Lockouts|r")
        lockoutY = lockoutY + 24  -- Increased spacing after title
        
        if pve.lockouts and #pve.lockouts > 0 then
            -- Group lockouts by raid name
            local raidGroups = {}
            local raidOrder = {}
            
            for _, lockout in ipairs(pve.lockouts) do
                local raidName = lockout.name or "Unknown"
                raidName = raidName:gsub("%s*%(.*%)%s*$", "")
                raidName = raidName:gsub("%s*%-.*$", "")
                raidName = raidName:gsub("%s+$", ""):gsub("^%s+", "")
                
                if not raidGroups[raidName] then
                    raidGroups[raidName] = {}
                    table.insert(raidOrder, raidName)
                end
                table.insert(raidGroups[raidName], lockout)
            end
            
            -- Collapsible raid grid (3x4 layout)
            local boxWidth = 50
            local boxHeight = 24
            local boxSpacing = 4
            local cols = 4
            local rows = 3
            local maxVisible = cols * rows -- 12 raids visible
            local startIndex = charCard.raidScrollOffset or 0
            
            -- Scroll buttons container
            if #raidOrder > maxVisible then
                if not charCard.scrollLeftBtn then
                    local leftBtn = CreateFrame("Button", nil, charCard, "BackdropTemplate")
                    leftBtn:SetSize(16, (rows * (boxHeight + boxSpacing)) - boxSpacing)
                    leftBtn:SetPoint("TOPLEFT", lockoutX + 10 + (cols * (boxWidth + boxSpacing)), -lockoutY)
                    leftBtn:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 1,
                    })
                    leftBtn:SetBackdropColor(0.1, 0.1, 0.12, 1)
                    leftBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
                    
                    local arrow = leftBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    arrow:SetPoint("CENTER")
                    arrow:SetText(">")
                    arrow:SetTextColor(0.7, 0.7, 0.7)
                    
                    leftBtn:SetScript("OnClick", function()
                        charCard.raidScrollOffset = (charCard.raidScrollOffset or 0) + maxVisible
                        if charCard.raidScrollOffset >= #raidOrder then
                            charCard.raidScrollOffset = 0
                        end
                        self:RefreshUI()
                    end)
                    
                    leftBtn:SetScript("OnEnter", function(btn)
                        btn:SetBackdropColor(0.15, 0.15, 0.18, 1)
                    end)
                    leftBtn:SetScript("OnLeave", function(btn)
                        btn:SetBackdropColor(0.1, 0.1, 0.12, 1)
                    end)
                    
                    charCard.scrollLeftBtn = leftBtn
                end
                charCard.scrollLeftBtn:Show()
            elseif charCard.scrollLeftBtn then
                charCard.scrollLeftBtn:Hide()
            end
            
            local raidCount = 0
            for i = startIndex + 1, math.min(startIndex + maxVisible, #raidOrder) do
                local raidName = raidOrder[i]
                local difficulties = raidGroups[raidName]
                
                local col = raidCount % cols
                local row = math.floor(raidCount / cols)
                
                -- Create raid box container
                local raidBar = CreateFrame("Button", nil, charCard, "BackdropTemplate")
                raidBar:SetSize(boxWidth, boxHeight)
                raidBar:SetPoint("TOPLEFT", lockoutX + 10 + (col * (boxWidth + boxSpacing)), -(lockoutY + (row * (boxHeight + boxSpacing))))
                
                raidBar:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                raidBar:SetBackdropColor(0.10, 0.10, 0.12, 1)
                raidBar:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
                
                -- Raid name abbreviated (centered)
                local initials = ""
                for word in raidName:gmatch("%S+") do
                    initials = initials .. word:sub(1, 1)
                    if #initials >= 3 then break end
                end
                
                local nameLabel = raidBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                nameLabel:SetPoint("CENTER", 0, 0)
                nameLabel:SetText(initials:upper())
                nameLabel:SetTextColor(0.8, 0.8, 0.8)
                nameLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
                
                -- Expanded state
                raidBar.expanded = false
                raidBar.difficulties = difficulties
                raidBar.raidName = raidName
                    
                -- Click to expand/collapse
                raidBar:SetScript("OnClick", function(self)
                    self.expanded = not self.expanded
                    
                    if self.expanded then
                        -- Show difficulties
                        if not self.diffFrame then
                            local diffFrame = CreateFrame("Frame", nil, self, "BackdropTemplate")
                            diffFrame:SetSize(boxWidth + 14, 38)
                            diffFrame:SetPoint("BOTTOM", self, "TOP", 0, 4)
                            diffFrame:SetBackdrop({
                                bgFile = "Interface\\Buttons\\WHITE8x8",
                                edgeFile = "Interface\\Buttons\\WHITE8x8",
                                edgeSize = 1,
                            })
                            diffFrame:SetBackdropColor(0.08, 0.08, 0.10, 1)
                            diffFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 1)
                            self.diffFrame = diffFrame
                            
                            -- Map difficulties
                            local diffMap = {L = nil, N = nil, H = nil, M = nil}
                            for _, lockout in ipairs(self.difficulties) do
                                local diffName = lockout.difficultyName or "Normal"
                                if diffName:find("Mythic") then
                                    diffMap.M = lockout
                                elseif diffName:find("Heroic") then
                                    diffMap.H = lockout
                                elseif diffName:find("Raid Finder") or diffName:find("LFR") then
                                    diffMap.L = lockout
                                else
                                    diffMap.N = lockout
                                end
                            end
                            
                            -- 2x2 grid layout: L N / H M (bigger cells)
                            local diffOrder = {
                                {key = "L", x = 0, y = 0, color = {1, 0.5, 0}},
                                {key = "N", x = 32, y = 0, color = {0.3, 0.9, 0.3}},
                                {key = "H", x = 0, y = -19, color = {0, 0.44, 0.87}},
                                {key = "M", x = 32, y = -19, color = {0.64, 0.21, 0.93}}
                            }
                            
                            for i, diff in ipairs(diffOrder) do
                                local lockout = diffMap[diff.key]
                                local cell = CreateFrame("Frame", nil, diffFrame, "BackdropTemplate")
                                cell:SetSize(30, 17)
                                cell:SetPoint("TOPLEFT", diff.x + 2, diff.y - 2)
                                
                                cell:SetBackdrop({
                                    bgFile = "Interface\\Buttons\\WHITE8x8",
                                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                                    edgeSize = 1,
                                })
                                
                                if lockout then
                                    local r, g, b = diff.color[1], diff.color[2], diff.color[3]
                                    cell:SetBackdropColor(r * 0.4, g * 0.4, b * 0.4, 1)
                                    cell:SetBackdropBorderColor(r, g, b, 1)
                                    
                                    local progress = lockout.progress or 0
                                    local total = lockout.total or 0
                                    if progress > total and total > 0 then progress = total end
                                    
                                    local cellText = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                                    cellText:SetPoint("CENTER", 0, 0)
                                    cellText:SetText(diff.key)
                                    cellText:SetTextColor(r, g, b, 1)
                                    cellText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
                                    
                                    -- Tooltip
                                    cell:EnableMouse(true)
                                    cell:SetScript("OnEnter", function(c)
                                        GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
                                        GameTooltip:SetText(self.raidName, 1, 1, 1)
                                        GameTooltip:AddLine(" ")
                                        local diffNames = {L = "LFR", N = "Normal", H = "Heroic", M = "Mythic"}
                                        GameTooltip:AddDoubleLine("Difficulty:", diffNames[diff.key], nil, nil, nil, r, g, b)
                                        local progressPct = total > 0 and (progress / total * 100) or 0
                                        local pc = progress == total and {0, 1, 0} or {1, 1, 0}
                                        GameTooltip:AddDoubleLine("Progress:", string.format("%d/%d (%.0f%%)", progress, total, progressPct), nil, nil, nil, pc[1], pc[2], pc[3])
                                        if lockout.reset then
                                            local timeLeft = lockout.reset - time()
                                            if timeLeft > 0 then
                                                local days = math.floor(timeLeft / 86400)
                                                local hours = math.floor((timeLeft % 86400) / 3600)
                                                local resetStr = days > 0 and string.format("%dd %dh", days, hours) or string.format("%dh", hours)
                                                GameTooltip:AddDoubleLine("Resets in:", resetStr, nil, nil, nil, 1, 1, 1)
                                            end
                                        end
                                        if lockout.extended then
                                            GameTooltip:AddLine(" ")
                                            GameTooltip:AddLine("|cffff8000[Extended]|r", 1, 0.5, 0)
                                        end
                                        GameTooltip:Show()
                                    end)
                                    cell:SetScript("OnLeave", function(c) GameTooltip:Hide() end)
                                else
                                    cell:SetBackdropColor(0.05, 0.05, 0.05, 0.5)
                                    cell:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.5)
                                    local cellText = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                                    cellText:SetPoint("CENTER", 0, 0)
                                    cellText:SetText(diff.key)
                                    cellText:SetTextColor(0.3, 0.3, 0.3, 0.5)
                                    cellText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
                                end
                            end
                        end
                        self.diffFrame:Show()
                    else
                        -- Hide difficulties
                        if self.diffFrame then
                            self.diffFrame:Hide()
                        end
                    end
                end)
                
                -- Hover highlight
                raidBar:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(0.15, 0.15, 0.18, 1)
                end)
                raidBar:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(0.10, 0.10, 0.12, 1)
                end)
                
                raidCount = raidCount + 1
            end
            
            local actualRows = math.ceil(math.min(raidCount, maxVisible) / cols)
            lockoutY = lockoutY + (actualRows * (boxHeight + boxSpacing)) + 5
        else
            local noLockouts = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noLockouts:SetPoint("TOPLEFT", lockoutX + 10, -lockoutY)
            noLockouts:SetText("|cff666666No lockouts|r")
            noLockouts:SetTextColor(0.5, 0.5, 0.5)
            lockoutY = lockoutY + 15
        end
        
        -- Calculate final height (use tallest column)
        local maxColumnHeight = math.max(vaultY, mplusY, lockoutY)
        cardYOffset = maxColumnHeight + 10
        
        -- Set card height
        charCard:SetHeight(cardYOffset)
        yOffset = yOffset + cardYOffset + 10
    end
    
    return yOffset + 20
end

