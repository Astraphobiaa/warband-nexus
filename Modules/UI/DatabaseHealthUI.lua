--[[
    Warband Nexus - Database Health UI
    Displays database statistics, compression info, and manual optimization controls
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local CreateCard = ns.UI_CreateCard

--[[
    Draw Database Health panel
    @param parent frame - Parent frame
]]
function WarbandNexus:DrawDatabaseHealth(parent)
    local yOffset = 10
    
    -- Title Card
    local titleCard = CreateCard(parent, 80)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(48, 48)
    titleIcon:SetPoint("LEFT", 20, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_EngGizmos_30")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 15, 8)
    titleText:SetText("Database Health")
    titleText:SetTextColor(1, 0.8, 0.2)
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 15, -12)
    subtitleText:SetText("Monitor and optimize database performance")
    subtitleText:SetTextColor(0.7, 0.7, 0.7)
    
    yOffset = yOffset + 90
    
    -- Compression Statistics Card
    local compressionCard = CreateCard(parent, 180)
    compressionCard:SetPoint("TOPLEFT", 10, -yOffset)
    compressionCard:SetWidth((parent:GetWidth() - 30) / 2)
    
    self:DrawCompressionStats(compressionCard)
    
    -- Performance Statistics Card
    local perfCard = CreateCard(parent, 180)
    perfCard:SetPoint("TOPRIGHT", -10, -yOffset)
    perfCard:SetWidth((parent:GetWidth() - 30) / 2)
    
    self:DrawPerformanceStats(perfCard)
    
    yOffset = yOffset + 190
    
    -- Memory Statistics Card
    local memoryCard = CreateCard(parent, 160)
    memoryCard:SetPoint("TOPLEFT", 10, -yOffset)
    memoryCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    self:DrawMemoryStats(memoryCard)
    
    yOffset = yOffset + 170
    
    -- Manual Controls Card
    local controlsCard = CreateCard(parent, 140)
    controlsCard:SetPoint("TOPLEFT", 10, -yOffset)
    controlsCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    self:DrawManualControls(controlsCard)
end

--[[
    Draw compression statistics
    @param card frame - Card frame
]]
function WarbandNexus:DrawCompressionStats(card)
    local stats = self:GetCompressionStats()
    
    -- Header
    local header = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 15, -15)
    header:SetText("Compression")
    header:SetTextColor(1, 0.8, 0.2)
    
    local yPos = 45
    
    -- Status
    local statusLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusLabel:SetPoint("TOPLEFT", 15, -yPos)
    statusLabel:SetText("Status:")
    
    local statusValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusValue:SetPoint("TOPRIGHT", -15, -yPos)
    if stats.isCompressed then
        statusValue:SetText("|cff00ff00Compressed|r")
    else
        statusValue:SetText("|cffffcc00Uncompressed|r")
    end
    
    yPos = yPos + 25
    
    -- Original Size
    local origLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    origLabel:SetPoint("TOPLEFT", 15, -yPos)
    origLabel:SetText("Original Size:")
    
    local origValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    origValue:SetPoint("TOPRIGHT", -15, -yPos)
    origValue:SetText(self:FormatBytes(stats.originalSize * 1024))
    
    yPos = yPos + 20
    
    -- Compressed Size
    local compLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compLabel:SetPoint("TOPLEFT", 15, -yPos)
    compLabel:SetText("Compressed Size:")
    
    local compValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compValue:SetPoint("TOPRIGHT", -15, -yPos)
    compValue:SetText(self:FormatBytes(stats.compressedSize * 1024))
    
    yPos = yPos + 20
    
    -- Compression Ratio
    local ratioLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ratioLabel:SetPoint("TOPLEFT", 15, -yPos)
    ratioLabel:SetText("Compression Ratio:")
    
    local ratioValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ratioValue:SetPoint("TOPRIGHT", -15, -yPos)
    ratioValue:SetText(string.format("%.1f%%", stats.ratio))
    ratioValue:SetTextColor(0.2, 0.9, 0.3)
    
    yPos = yPos + 25
    
    -- Character Counts
    local charLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charLabel:SetPoint("TOPLEFT", 15, -yPos)
    charLabel:SetText("Characters:")
    
    local charValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charValue:SetPoint("TOPRIGHT", -15, -yPos)
    charValue:SetText(string.format("%d active, %d archived", 
        stats.characterCount, stats.archivedCount))
end

--[[
    Draw performance statistics
    @param card frame - Card frame
]]
function WarbandNexus:DrawPerformanceStats(card)
    local memStats = self:GetMemoryStats()
    local fpsStats = self:GetFPSStats()
    
    -- Header
    local header = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 15, -15)
    header:SetText("Performance")
    header:SetTextColor(1, 0.8, 0.2)
    
    local yPos = 45
    
    -- Memory Usage
    local memLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    memLabel:SetPoint("TOPLEFT", 15, -yPos)
    memLabel:SetText("Memory Usage:")
    
    local memValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    memValue:SetPoint("TOPRIGHT", -15, -yPos)
    memValue:SetText(string.format("%.2f MB", memStats.current / 1024))
    
    yPos = yPos + 25
    
    -- Average Memory
    local avgMemLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    avgMemLabel:SetPoint("TOPLEFT", 15, -yPos)
    avgMemLabel:SetText("Average:")
    
    local avgMemValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    avgMemValue:SetPoint("TOPRIGHT", -15, -yPos)
    avgMemValue:SetText(string.format("%.2f MB", memStats.average / 1024))
    
    yPos = yPos + 20
    
    -- Peak Memory
    local peakMemLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    peakMemLabel:SetPoint("TOPLEFT", 15, -yPos)
    peakMemLabel:SetText("Peak:")
    
    local peakMemValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    peakMemValue:SetPoint("TOPRIGHT", -15, -yPos)
    peakMemValue:SetText(string.format("%.2f MB", memStats.max / 1024))
    
    yPos = yPos + 25
    
    -- FPS
    local fpsLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fpsLabel:SetPoint("TOPLEFT", 15, -yPos)
    fpsLabel:SetText("Frame Rate:")
    
    local fpsValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fpsValue:SetPoint("TOPRIGHT", -15, -yPos)
    fpsValue:SetText(string.format("%.1f FPS", fpsStats.current))
    
    if fpsStats.current < 30 then
        fpsValue:SetTextColor(1, 0.3, 0.3)
    elseif fpsStats.current < 60 then
        fpsValue:SetTextColor(1, 0.8, 0.2)
    else
        fpsValue:SetTextColor(0.2, 0.9, 0.3)
    end
end

--[[
    Draw memory statistics
    @param card frame - Card frame
]]
function WarbandNexus:DrawMemoryStats(card)
    local poolStats = self:GetMemoryStats()
    local indexStats = self:GetSearchIndexStats()
    
    -- Header
    local header = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 15, -15)
    header:SetText("Memory Optimization")
    header:SetTextColor(1, 0.8, 0.2)
    
    local yPos = 45
    
    -- Search Index
    local indexLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    indexLabel:SetPoint("TOPLEFT", 15, -yPos)
    indexLabel:SetText("Search Index:")
    
    local indexValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    indexValue:SetPoint("TOPRIGHT", -15, -yPos)
    indexValue:SetText(string.format("%d items", indexStats.uniqueItems))
    
    yPos = yPos + 25
    
    -- Index Status
    local indexStatusLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    indexStatusLabel:SetPoint("TOPLEFT", 15, -yPos)
    indexStatusLabel:SetText("Status:")
    
    local indexStatusValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    indexStatusValue:SetPoint("TOPRIGHT", -15, -yPos)
    if indexStats.isStale then
        indexStatusValue:SetText("|cffffcc00Stale|r")
    else
        indexStatusValue:SetText("|cff00ff00Fresh|r")
    end
    
    yPos = yPos + 20
    
    -- Index Age
    local ageLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ageLabel:SetPoint("TOPLEFT", 15, -yPos)
    ageLabel:SetText("Last Rebuild:")
    
    local ageValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ageValue:SetPoint("TOPRIGHT", -15, -yPos)
    local age = indexStats.age
    if age < 60 then
        ageValue:SetText(string.format("%d seconds ago", age))
    elseif age < 3600 then
        ageValue:SetText(string.format("%d minutes ago", math.floor(age / 60)))
    else
        ageValue:SetText(string.format("%d hours ago", math.floor(age / 3600)))
    end
    
    yPos = yPos + 25
    
    -- Coroutines
    local coStats = self:GetCoroutineStats()
    local coLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    coLabel:SetPoint("TOPLEFT", 15, -yPos)
    coLabel:SetText("Active Coroutines:")
    
    local coValue = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    coValue:SetPoint("TOPRIGHT", -15, -yPos)
    coValue:SetText(tostring(coStats.activeCoroutines))
end

--[[
    Draw manual control buttons
    @param card frame - Card frame
]]
function WarbandNexus:DrawManualControls(card)
    -- Header
    local header = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 15, -15)
    header:SetText("Manual Controls")
    header:SetTextColor(1, 0.8, 0.2)
    
    local yPos = 50
    
    -- Compress Now Button
    local compressBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    compressBtn:SetSize(180, 30)
    compressBtn:SetPoint("TOP", 0, -yPos)
    compressBtn:SetText("Compress Database")
    compressBtn:SetScript("OnClick", function()
        WarbandNexus:ManualCompress()
    end)
    compressBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Compress Database", 1, 1, 1)
        GameTooltip:AddLine("Manually compress the database to reduce size.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    compressBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    yPos = yPos + 40
    
    -- Rebuild Index Button
    local indexBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    indexBtn:SetSize(180, 30)
    indexBtn:SetPoint("TOP", 0, -yPos)
    indexBtn:SetText("Rebuild Search Index")
    indexBtn:SetScript("OnClick", function()
        WarbandNexus:RebuildSearchIndex(true)
        WarbandNexus:Print("|cff00ff00Search index rebuilt!|r")
    end)
    indexBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Rebuild Search Index", 1, 1, 1)
        GameTooltip:AddLine("Rebuild the search index for faster item lookups.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    indexBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

