--[[
    Warband Nexus - PvE Module
    Displays Great Vault, Mythic+ Keystone, and Raid Lockouts for all characters
    
    This module provides UI components for tracking PvE progression across the warband:
    - Great Vault rewards and progress
    - Current Mythic+ Keystones
    - Raid Lockouts and boss kills
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- Color constants
local QUALITY_COLORS = {
    [0] = "ff9d9d9d", -- Poor (Gray)
    [1] = "ffffffff", -- Common (White)
    [2] = "ff1eff00", -- Uncommon (Green)
    [3] = "ff0070dd", -- Rare (Blue)
    [4] = "ffa335ee", -- Epic (Purple)
    [5] = "ffff8000", -- Legendary (Orange)
}

local DIFFICULTY_COLORS = {
    [1] = "ff1eff00",  -- Normal (Green)
    [2] = "ff0070dd",  -- Heroic (Blue)
    [3] = "ffa335ee",  -- Mythic (Purple)
    [4] = "ffff8000",  -- Mythic+ (Orange)
}

-- Activity type mapping for Great Vault
local VAULT_ACTIVITY_TYPE = {
    [1] = "Raid",
    [2] = "Mythic+",
    [3] = "PvP",
}

--[[
    Create PvE display frame
    @param parent Frame - Parent frame to attach to
    @return Frame - The created PvE frame
]]
function WarbandNexus:CreatePvEFrame(parent)
    local frame = CreateFrame("Frame", "WarbandNexusPvEFrame", parent)
    frame:SetAllPoints(parent)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText("|cff00ff00PvE Progression|r")
    frame.title = title
    
    -- Scroll frame for character list
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -40, 20)
    frame.scrollFrame = scrollFrame
    
    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth() or 600, 1) -- Height will be dynamic
    scrollFrame:SetScrollChild(content)
    frame.content = content
    
    -- Character rows will be added dynamically
    frame.characterRows = {}
    
    return frame
end

--[[
    Refresh PvE display with current data
]]
function WarbandNexus:RefreshPvEUI()
    if not self.UI or not self.UI.pveFrame then
        return
    end
    
    local frame = self.UI.pveFrame
    local content = frame.content
    
    -- Clear existing rows
    for _, row in ipairs(frame.characterRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(frame.characterRows)
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    
    local yOffset = -10
    local rowHeight = 120
    
    for i, char in ipairs(characters) do
        local row = self:CreatePvECharacterRow(content, char, i)
        row:SetPoint("TOPLEFT", 10, yOffset)
        row:SetPoint("TOPRIGHT", -10, yOffset)
        row:SetHeight(rowHeight)
        
        table.insert(frame.characterRows, row)
        yOffset = yOffset - rowHeight - 10
    end
    
    -- Update content height
    content:SetHeight(math.abs(yOffset) + 20)
end

--[[
    Create a character row displaying PvE info
    @param parent Frame - Parent frame
    @param charData table - Character data
    @param index number - Row index
    @return Frame - The character row frame
]]
function WarbandNexus:CreatePvECharacterRow(parent, charData, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    row:SetBackdropColor(0, 0, 0, 0.6)
    row:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Character name and class
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("TOPLEFT", 10, -10)
    
    local classColor = RAID_CLASS_COLORS[charData.classFile] or { r = 1, g = 1, b = 1 }
    local colorHex = string.format("%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
    nameText:SetText(string.format("|cff%s%s|r - Level %d %s",
        colorHex,
        charData.name or "Unknown",
        charData.level or 0,
        charData.class or ""
    ))
    
    row.nameText = nameText
    
    -- PvE data sections
    local charKey = (charData.name or "Unknown") .. "-" .. (charData.realm or "Unknown")
    local pveData = self:GetPvEDataV2(charKey) or charData.pve or {}
    
    -- Great Vault section
    self:CreateVaultSection(row, pveData.greatVault or {})
    
    -- Mythic+ section
    self:CreateMythicPlusSection(row, pveData.mythicPlus or {})
    
    -- Lockouts section
    self:CreateLockoutsSection(row, pveData.lockouts or {})
    
    return row
end

--[[
    Create Great Vault progress section
    @param parent Frame - Parent frame
    @param vaultData table - Great Vault data
]]
function WarbandNexus:CreateVaultSection(parent, vaultData)
    local section = CreateFrame("Frame", nil, parent)
    section:SetPoint("TOPLEFT", 10, -35)
    section:SetSize(180, 70)
    
    local title = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("|cffffcc00Great Vault|r")
    
    -- Group activities by type
    local grouped = { Raid = {}, ["Mythic+"] = {}, PvP = {} }
    for _, activity in ipairs(vaultData) do
        local activityType = VAULT_ACTIVITY_TYPE[activity.type] or "Other"
        table.insert(grouped[activityType] or grouped["Other"], activity)
    end
    
    local yOffset = -20
    for activityType, activities in pairs(grouped) do
        if #activities > 0 then
            local text = section:CreateFontString(nil, "OVERLAY", "GameFontSmall")
            text:SetPoint("TOPLEFT", 5, yOffset)
            
            -- Count completed slots
            local completed = 0
            for _, act in ipairs(activities) do
                if act.progress >= act.threshold then
                    completed = completed + 1
                end
            end
            
            local color = completed >= #activities and "ff00ff00" or "ffffff00"
            text:SetText(string.format("|cff%s%s: %d/%d|r", color, activityType, completed, #activities))
            yOffset = yOffset - 15
        end
    end
    
    -- Show "No Data" if empty
    if #vaultData == 0 then
        local noData = section:CreateFontString(nil, "OVERLAY", "GameFontSmall")
        noData:SetPoint("TOPLEFT", 5, -20)
        noData:SetText("|cff888888No vault data|r")
    end
    
    parent.vaultSection = section
end

--[[
    Create Mythic+ Keystone section
    @param parent Frame - Parent frame
    @param mythicData table - Mythic+ data
]]
function WarbandNexus:CreateMythicPlusSection(parent, mythicData)
    local section = CreateFrame("Frame", nil, parent)
    section:SetPoint("TOP", parent, "TOP", 0, -35)
    section:SetSize(180, 70)
    
    local title = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("|cffffcc00Mythic+|r")
    
    local yOffset = -20
    
    -- Current keystone
    if mythicData.keystone then
        local keystoneText = section:CreateFontString(nil, "OVERLAY", "GameFontSmall")
        keystoneText:SetPoint("TOPLEFT", 5, yOffset)
        keystoneText:SetText(string.format("|cffff8000+%d %s|r",
            mythicData.keystone.level or 0,
            mythicData.keystone.name or "Unknown"
        ))
        yOffset = yOffset - 15
    end
    
    -- Weekly best
    if mythicData.weeklyBest then
        local bestText = section:CreateFontString(nil, "OVERLAY", "GameFontSmall")
        bestText:SetPoint("TOPLEFT", 5, yOffset)
        bestText:SetText(string.format("Best: |cff00ff00+%d|r", mythicData.weeklyBest))
        yOffset = yOffset - 15
    end
    
    -- Runs this week
    if mythicData.runsThisWeek then
        local runsText = section:CreateFontString(nil, "OVERLAY", "GameFontSmall")
        runsText:SetPoint("TOPLEFT", 5, yOffset)
        runsText:SetText(string.format("Runs: |cff00ff00%d|r", mythicData.runsThisWeek))
    end
    
    -- Show "No Keystone" if no data
    if not mythicData.keystone and not mythicData.weeklyBest then
        local noData = section:CreateFontString(nil, "OVERLAY", "GameFontSmall")
        noData:SetPoint("TOPLEFT", 5, -20)
        noData:SetText("|cff888888No keystone|r")
    end
    
    parent.mythicSection = section
end

--[[
    Create Raid Lockouts section
    @param parent Frame - Parent frame
    @param lockoutData table - Lockout data
]]
function WarbandNexus:CreateLockoutsSection(parent, lockoutData)
    local section = CreateFrame("Frame", nil, parent)
    section:SetPoint("TOPRIGHT", -10, -35)
    section:SetSize(180, 70)
    
    local title = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("|cffffcc00Raid Lockouts|r")
    
    local yOffset = -20
    
    -- Show only active lockouts (max 3 for space)
    local shown = 0
    for _, lockout in ipairs(lockoutData) do
        if shown >= 3 then break end
        
        local lockoutText = section:CreateFontString(nil, "OVERLAY", "GameFontSmall")
        lockoutText:SetPoint("TOPLEFT", 5, yOffset)
        
        -- Format: "Raid Name (H) 5/8"
        local diffShort = lockout.difficultyName
        if diffShort then
            diffShort = diffShort:sub(1, 1) -- First letter only (N/H/M)
        else
            diffShort = "?"
        end
        
        local progressColor = lockout.progress == lockout.total and "ff00ff00" or "ffffff00"
        lockoutText:SetText(string.format("%s |cff888888(%s)|r |cff%s%d/%d|r",
            lockout.name or "Unknown",
            diffShort,
            progressColor,
            lockout.progress or 0,
            lockout.total or 0
        ))
        
        yOffset = yOffset - 15
        shown = shown + 1
    end
    
    -- Show "No Lockouts" if empty
    if #lockoutData == 0 then
        local noData = section:CreateFontString(nil, "OVERLAY", "GameFontSmall")
        noData:SetPoint("TOPLEFT", 5, -20)
        noData:SetText("|cff888888No lockouts|r")
    end
    
    -- Show "+ X more" if there are more lockouts
    if #lockoutData > 3 then
        local moreText = section:CreateFontString(nil, "OVERLAY", "GameFontSmall")
        moreText:SetPoint("TOPLEFT", 5, yOffset)
        moreText:SetText(string.format("|cff888888+ %d more|r", #lockoutData - 3))
    end
    
    parent.lockoutSection = section
end

--[[
    Format time remaining for lockouts
    @param resetTime number - Unix timestamp of reset
    @return string - Formatted time string
]]
local function FormatTimeRemaining(resetTime)
    if not resetTime or resetTime <= 0 then
        return "Unknown"
    end
    
    local remaining = resetTime - time()
    if remaining <= 0 then
        return "Expired"
    end
    
    local days = math.floor(remaining / 86400)
    local hours = math.floor((remaining % 86400) / 3600)
    
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    else
        return string.format("%dh", hours)
    end
end

-- Export functions to WarbandNexus namespace
ns.PvE = {
    CreatePvEFrame = function(...) return WarbandNexus:CreatePvEFrame(...) end,
    RefreshPvEUI = function(...) return WarbandNexus:RefreshPvEUI(...) end,
}

