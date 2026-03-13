--[[
    Warband Nexus - Profession Info Window
    Read-only detail window showing profession data for any character from DB.
    No API calls — all data comes from db.global.characters[charKey].

    Shows: expansion skills, concentration, knowledge (spec tabs with node details),
    equipment, recipe list, weekly knowledge progress, cooldowns.

    Opened via "Info" button next to "Open" in ProfessionsUI.
    If no data exists for the character: shows "Please login and open Profession window" message.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS or { accent = { 0.5, 0.4, 0.7 }, accentDark = { 0.25, 0.2, 0.35 } }
local ApplyVisuals = ns.UI_ApplyVisuals

-- Layout constants
local PADDING = 12
local SCROLLBAR_WIDTH = 22
local HEADER_HEIGHT = 40
local SECTION_GAP = 10
local LINE_HEIGHT = 18
local NODE_LINE_HEIGHT = 16
local LABEL_WIDTH = 155
local WINDOW_WIDTH = 440
local WINDOW_HEIGHT = 560
local CONTENT_WIDTH = WINDOW_WIDTH - PADDING * 2 - SCROLLBAR_WIDTH

-- Colors
local LABEL_COLOR = { 0.7, 0.7, 0.7 }
local VALUE_COLOR = { 1, 1, 1 }
local GREEN = { 0.3, 0.9, 0.3 }
local YELLOW = { 1, 0.82, 0 }
local DIM = { 0.45, 0.45, 0.45 }
local NODE_ALLOCATED = { 0.6, 0.85, 1 }
local NODE_UNALLOCATED = { 0.4, 0.4, 0.4 }

local format = string.format

-- Singleton frame
local infoFrame = nil

-- ============================================================================
-- HELPERS
-- ============================================================================

local function ColorText(text, color)
    if not color then return "|cffffffff" .. tostring(text) .. "|r" end
    return format("|cff%02x%02x%02x%s|r", color[1]*255, color[2]*255, color[3]*255, tostring(text))
end

local function ValueMax(current, maximum, color)
    if not current or not maximum or maximum <= 0 then return ColorText("--", LABEL_COLOR) end
    color = color or VALUE_COLOR
    return ColorText(current, color) .. " / " .. ColorText(maximum, color)
end

local function ProgressColor(current, maximum)
    if not current or not maximum or maximum <= 0 then return VALUE_COLOR end
    if current >= maximum then return GREEN end
    if current > 0 then return YELLOW end
    return VALUE_COLOR
end

local function AccentHex()
    return (ns.UI_GetAccentHexColor and ns.UI_GetAccentHexColor()) or "9966cc"
end

-- ============================================================================
-- SCROLL CONTENT BUILDER
-- ============================================================================

local function AddSectionHeader(scrollChild, yOffset, text)
    yOffset = yOffset + SECTION_GAP
    local header = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
    header:SetPoint("TOPLEFT", PADDING, -yOffset)
    header:SetWidth(CONTENT_WIDTH)
    header:SetJustifyH("LEFT")
    header:SetText("|cff" .. AccentHex() .. text .. "|r")
    yOffset = yOffset + LINE_HEIGHT + 2

    local line = scrollChild:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", PADDING, -yOffset)
    line:SetSize(CONTENT_WIDTH, 1)
    line:SetColorTexture(1, 1, 1, 0.1)
    yOffset = yOffset + 4
    return yOffset
end

local function AddLine(scrollChild, yOffset, label, value, indent)
    indent = indent or 0
    local lbl = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
    lbl:SetPoint("TOPLEFT", PADDING + indent, -yOffset)
    lbl:SetWidth(LABEL_WIDTH - indent)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetText(ColorText(label, LABEL_COLOR))

    local val = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
    val:SetPoint("TOPLEFT", PADDING + LABEL_WIDTH + 5, -yOffset)
    val:SetPoint("RIGHT", scrollChild, "RIGHT", -PADDING, 0)
    val:SetJustifyH("LEFT")
    val:SetWordWrap(false)
    val:SetText(value or ColorText("--", LABEL_COLOR))

    return yOffset + LINE_HEIGHT
end

local function AddFullWidthLine(scrollChild, yOffset, text, indent)
    indent = indent or 0
    local fs = FontManager:CreateFontString(scrollChild, "small", "OVERLAY")
    fs:SetPoint("TOPLEFT", PADDING + indent, -yOffset)
    fs:SetWidth(CONTENT_WIDTH - indent)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetText(text)
    return yOffset + NODE_LINE_HEIGHT
end

local function AddEmptyMessage(scrollChild, yOffset, message)
    yOffset = yOffset + 20
    local msg = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
    msg:SetPoint("TOPLEFT", PADDING, -yOffset)
    msg:SetWidth(CONTENT_WIDTH)
    msg:SetJustifyH("CENTER")
    msg:SetWordWrap(true)
    msg:SetText(ColorText(message, YELLOW))
    return yOffset + LINE_HEIGHT * 3
end

-- ============================================================================
-- POPULATE WINDOW CONTENT
-- ============================================================================

local function PopulateContent(scrollChild, charData, charKey, profName, profSlot)
    -- Clear previous content
    local regions = { scrollChild:GetRegions() }
    for _, region in ipairs(regions) do
        region:Hide()
        region:SetParent(nil)
    end
    local children = { scrollChild:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    local yOffset = PADDING

    -- Check if we have any profession data for this character
    local hasExpansions = charData.professionExpansions and charData.professionExpansions[profName] and #charData.professionExpansions[profName] > 0
    local hasConcentration = false
    local hasKnowledge = false
    local hasRecipes = false
    local hasEquipment = false
    local hasCooldowns = false

    -- Find relevant skillLineIDs for this profession
    local relevantSkillLines = {}
    if charData.professionExpansions and charData.professionExpansions[profName] then
        for _, exp in ipairs(charData.professionExpansions[profName]) do
            if exp.skillLineID then
                relevantSkillLines[#relevantSkillLines + 1] = exp.skillLineID
            end
        end
    end

    -- Check data availability
    if charData.concentration then
        for _, slID in ipairs(relevantSkillLines) do
            if charData.concentration[slID] then hasConcentration = true; break end
        end
    end
    if charData.knowledgeData then
        for _, slID in ipairs(relevantSkillLines) do
            if charData.knowledgeData[slID] then hasKnowledge = true; break end
        end
    end
    if charData.recipes then
        for _, slID in ipairs(relevantSkillLines) do
            if charData.recipes[slID] then hasRecipes = true; break end
        end
    end

    local eqKey = profName:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", ""):gsub("^Shadowlands ", "")
    local eqData = charData.professionEquipment and (charData.professionEquipment[profName] or charData.professionEquipment[eqKey])
    if not eqData and charData.professionEquipment then
        for k, v in pairs(charData.professionEquipment) do
            if k ~= "_legacy" and type(v) == "table" then
                local norm = k:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", "")
                if norm == eqKey then eqData = v; break end
            end
        end
    end
    hasEquipment = eqData and (eqData.tool or eqData.accessory1 or eqData.accessory2) or false

    if charData.professionCooldowns then
        for _, slID in ipairs(relevantSkillLines) do
            if charData.professionCooldowns[slID] and next(charData.professionCooldowns[slID]) then
                hasCooldowns = true; break
            end
        end
    end

    local hasAnyData = hasExpansions or hasConcentration or hasKnowledge or hasRecipes or hasEquipment or hasCooldowns

    if not hasAnyData then
        yOffset = AddEmptyMessage(scrollChild, yOffset,
            (ns.L and ns.L["PROF_INFO_NO_DATA"]) or "No profession data available.\nPlease login on this character and open the Profession window (K) to collect data.")
        scrollChild:SetHeight(yOffset + PADDING)
        return
    end

    -- ===== EXPANSION SKILLS =====
    if hasExpansions then
        yOffset = AddSectionHeader(scrollChild, yOffset, (ns.L and ns.L["PROF_INFO_SKILLS"]) or "Expansion Skills")
        local expansions = charData.professionExpansions[profName]
        for _, exp in ipairs(expansions) do
            local cur = exp.skillLevel or 0
            local mx = exp.maxSkillLevel or 0
            local color = ProgressColor(cur, mx)
            yOffset = AddLine(scrollChild, yOffset, exp.name or "?", ValueMax(cur, mx, color))
        end
    end

    -- ===== CONCENTRATION =====
    if hasConcentration then
        yOffset = AddSectionHeader(scrollChild, yOffset, (ns.L and ns.L["CONCENTRATION"]) or "Concentration")
        for _, slID in ipairs(relevantSkillLines) do
            local concData = charData.concentration[slID]
            if concData and concData.max and concData.max > 0 then
                local current = concData.current or 0
                if WarbandNexus.GetEstimatedConcentration then
                    current = WarbandNexus:GetEstimatedConcentration(concData)
                end
                local color = ProgressColor(current, concData.max)
                local expLabel = concData.expansionName or concData.professionName or ("SkillLine " .. slID)
                yOffset = AddLine(scrollChild, yOffset, expLabel, ValueMax(current, concData.max, color))

                -- Recharge time
                if current < concData.max and WarbandNexus.GetConcentrationTimeToFull then
                    local ts = WarbandNexus:GetConcentrationTimeToFull(concData)
                    if ts and ts ~= "" and ts ~= "Full" then
                        yOffset = AddLine(scrollChild, yOffset, (ns.L and ns.L["RECHARGE"]) or "Recharge", ColorText(ts, YELLOW), 10)
                    end
                end
            end
        end
    end

    -- ===== KNOWLEDGE & TALENT TREES =====
    if hasKnowledge then
        yOffset = AddSectionHeader(scrollChild, yOffset, (ns.L and ns.L["KNOWLEDGE"]) or "Knowledge")
        for _, slID in ipairs(relevantSkillLines) do
            local kd = charData.knowledgeData[slID]
            if kd then
                local spent = kd.spentPoints or 0
                local unspent = kd.unspentPoints or 0
                local maxPts = kd.maxPoints or 0
                local current = spent + unspent
                local color = ProgressColor(current, maxPts)
                local label = kd.expansionName or kd.professionName or ("SkillLine " .. slID)
                yOffset = AddLine(scrollChild, yOffset, label, ValueMax(current, maxPts, color))

                if spent > 0 then
                    yOffset = AddLine(scrollChild, yOffset, (ns.L and ns.L["PROF_INFO_SPENT"]) or "Spent", ColorText(spent, VALUE_COLOR), 10)
                end
                if unspent > 0 then
                    yOffset = AddLine(scrollChild, yOffset, (ns.L and ns.L["UNSPENT_POINTS"]) or "Unspent", ColorText(unspent, YELLOW), 10)
                end

                -- Specialization Tabs with Node Details
                if kd.specTabs and #kd.specTabs > 0 then
                    yOffset = yOffset + 6
                    for _, tab in ipairs(kd.specTabs) do
                        -- Tab header line
                        local stateTxt = tab.state or "?"
                        local isUnlocked = (stateTxt == "1" or stateTxt:lower() == "unlocked")
                        local stateColor = isUnlocked and GREEN or LABEL_COLOR
                        local stateLabel = isUnlocked and ((ns.L and ns.L["PROF_INFO_UNLOCKED"]) or "Unlocked") or ((ns.L and ns.L["PROF_INFO_LOCKED"]) or "Locked")
                        yOffset = AddLine(scrollChild, yOffset, tab.name or "?", ColorText(stateLabel, stateColor), 10)

                        -- Node details for this tab
                        if tab.nodes and #tab.nodes > 0 then
                            local allocatedCount = 0
                            local totalRanks = 0
                            local spentRanks = 0
                            for _, node in ipairs(tab.nodes) do
                                totalRanks = totalRanks + (node.maxRanks or 0)
                                spentRanks = spentRanks + (node.currentRank or 0)
                                if (node.currentRank or 0) > 0 then
                                    allocatedCount = allocatedCount + 1
                                end
                            end

                            -- Summary: allocated nodes / total nodes, spent ranks / total ranks
                            local summaryText = ColorText(allocatedCount, NODE_ALLOCATED)
                                .. ColorText(" / " .. #tab.nodes .. " nodes, ", DIM)
                                .. ColorText(spentRanks, NODE_ALLOCATED)
                                .. ColorText(" / " .. totalRanks .. " ranks", DIM)
                            yOffset = AddFullWidthLine(scrollChild, yOffset, summaryText, 20)

                            -- Individual nodes (only allocated ones to keep it clean)
                            for _, node in ipairs(tab.nodes) do
                                if (node.currentRank or 0) > 0 then
                                    local nodeColor = (node.currentRank >= node.maxRanks) and GREEN or NODE_ALLOCATED
                                    local rankStr = ColorText(node.currentRank .. "/" .. node.maxRanks, nodeColor)
                                    local nameStr = ColorText(node.name or "?", (node.currentRank >= node.maxRanks) and VALUE_COLOR or NODE_ALLOCATED)
                                    yOffset = AddFullWidthLine(scrollChild, yOffset, "  " .. nameStr .. "  " .. rankStr, 20)
                                end
                            end
                            yOffset = yOffset + 2
                        end
                    end
                end
            end
        end
    end

    -- ===== EQUIPMENT =====
    if hasEquipment then
        yOffset = AddSectionHeader(scrollChild, yOffset, (ns.L and ns.L["EQUIPMENT"]) or "Equipment")
        local slotLabels = {
            tool = (ns.L and ns.L["PROF_INFO_TOOL"]) or "Tool",
            accessory1 = (ns.L and ns.L["PROF_INFO_ACC1"]) or "Accessory 1",
            accessory2 = (ns.L and ns.L["PROF_INFO_ACC2"]) or "Accessory 2",
        }
        for _, slotKey in ipairs({ "tool", "accessory1", "accessory2" }) do
            local item = eqData[slotKey]
            if item then
                local iconStr = item.icon and format("|T%s:0|t ", tostring(item.icon)) or ""
                yOffset = AddLine(scrollChild, yOffset, slotLabels[slotKey], iconStr .. ColorText(item.name or "Unknown", VALUE_COLOR))
            end
        end
    end

    -- ===== RECIPES =====
    if hasRecipes then
        yOffset = AddSectionHeader(scrollChild, yOffset, (ns.L and ns.L["RECIPES"]) or "Recipes")
        for _, slID in ipairs(relevantSkillLines) do
            local rd = charData.recipes[slID]
            if rd then
                -- Summary line
                local label = rd.expansionName or rd.professionName or ("SkillLine " .. slID)
                local knownColor = ProgressColor(rd.knownCount or 0, rd.totalCount or 0)
                yOffset = AddLine(scrollChild, yOffset, label .. " " .. ((ns.L and ns.L["PROF_INFO_KNOWN"]) or "Known"),
                    ValueMax(rd.knownCount or 0, rd.totalCount or 0, knownColor))

                if rd.firstCraftTotalCount and rd.firstCraftTotalCount > 0 then
                    local fcColor = ProgressColor(rd.firstCraftDoneCount or 0, rd.firstCraftTotalCount)
                    yOffset = AddLine(scrollChild, yOffset, (ns.L and ns.L["FIRST_CRAFT"]) or "First Craft",
                        ValueMax(rd.firstCraftDoneCount or 0, rd.firstCraftTotalCount, fcColor), 10)
                end

                -- Recipe list (detailed)
                if rd.recipeList and #rd.recipeList > 0 then
                    yOffset = yOffset + 4
                    -- Sort: learned first, then alphabetical
                    local sorted = {}
                    for idx = 1, #rd.recipeList do
                        sorted[#sorted + 1] = rd.recipeList[idx]
                    end
                    table.sort(sorted, function(a, b)
                        if a.learned ~= b.learned then return a.learned end
                        return (a.name or "") < (b.name or "")
                    end)

                    for _, recipe in ipairs(sorted) do
                        local iconStr = recipe.icon and format("|T%s:14:14:0:0|t ", tostring(recipe.icon)) or ""
                        local nameColor = recipe.learned and VALUE_COLOR or DIM
                        local statusStr = recipe.learned and "" or ("  " .. ColorText("(" .. ((ns.L and ns.L["PROF_INFO_UNLEARNED"]) or "Unlearned") .. ")", DIM))
                        yOffset = AddFullWidthLine(scrollChild, yOffset, iconStr .. ColorText(recipe.name or "?", nameColor) .. statusStr, 10)
                    end
                end
            end
        end
    end

    -- ===== WEEKLY KNOWLEDGE PROGRESS (Midnight) =====
    local hasWeeklyProgress = false
    local weeklyData = {}
    for _, slID in ipairs(relevantSkillLines) do
        local bucket = charData.professionData and charData.professionData.bySkillLine and charData.professionData.bySkillLine[slID]
        local progress = bucket and bucket.weeklyKnowledge
        if not progress and charData.professionWeeklyKnowledge then
            progress = charData.professionWeeklyKnowledge[slID]
        end
        if progress then
            weeklyData[slID] = progress
            hasWeeklyProgress = true
        end
    end

    if hasWeeklyProgress then
        yOffset = AddSectionHeader(scrollChild, yOffset, (ns.L and ns.L["PROF_INFO_WEEKLY"]) or "Weekly Knowledge Progress")
        local sourceKeys = { "uniques", "treatise", "weeklyQuest", "treasure", "gathering", "catchUp" }
        local sourceLabels = {
            uniques = (ns.L and ns.L["UNIQUES"]) or "Uniques",
            treatise = (ns.L and ns.L["TREATISE"]) or "Treatise",
            weeklyQuest = (ns.L and ns.L["WEEKLY_QUEST_CAT"]) or "Weekly Quest",
            treasure = (ns.L and ns.L["SOURCE_TYPE_TREASURE"]) or "Treasure",
            gathering = (ns.L and ns.L["GATHERING"]) or "Gathering",
            catchUp = (ns.L and ns.L["CATCH_UP"]) or "Catch Up",
        }
        for _, progress in pairs(weeklyData) do
            for _, key in ipairs(sourceKeys) do
                local entry = progress[key]
                if entry and entry.total and entry.total > 0 then
                    local color = ProgressColor(entry.current or 0, entry.total)
                    yOffset = AddLine(scrollChild, yOffset, sourceLabels[key] or key,
                        ValueMax(entry.current or 0, entry.total, color))
                end
            end
            break -- Only show first matching skillLine's weekly data
        end
    end

    -- ===== COOLDOWNS =====
    if hasCooldowns then
        yOffset = AddSectionHeader(scrollChild, yOffset, (ns.L and ns.L["PROF_INFO_COOLDOWNS"]) or "Cooldowns")
        local now = time()
        for _, slID in ipairs(relevantSkillLines) do
            local cdTable = charData.professionCooldowns[slID]
            if cdTable then
                for recipeID, cd in pairs(cdTable) do
                    local iconStr = cd.recipeIcon and format("|T%s:0|t ", tostring(cd.recipeIcon)) or ""
                    local statusText
                    if cd.cooldownEnd and cd.cooldownEnd > now then
                        local remaining = cd.cooldownEnd - now
                        local hours = math.floor(remaining / 3600)
                        local minutes = math.floor((remaining % 3600) / 60)
                        if hours > 0 then
                            statusText = ColorText(format("%dh %dm", hours, minutes), YELLOW)
                        else
                            statusText = ColorText(format("%dm", math.max(1, minutes)), YELLOW)
                        end
                    else
                        statusText = ColorText((ns.L and ns.L["PROF_INFO_READY"]) or "Ready", GREEN)
                    end
                    yOffset = AddLine(scrollChild, yOffset, iconStr .. (cd.recipeName or "Unknown"), statusText)
                end
            end
        end
    end

    -- ===== LAST UPDATE =====
    yOffset = yOffset + SECTION_GAP
    local lastUpdate = 0
    if charData.professionData and charData.professionData.lastUpdate then
        lastUpdate = charData.professionData.lastUpdate
    end
    if lastUpdate > 0 then
        local elapsed = time() - lastUpdate
        local timeStr
        if elapsed < 60 then timeStr = "< 1m ago"
        elseif elapsed < 3600 then timeStr = format("%dm ago", math.floor(elapsed / 60))
        elseif elapsed < 86400 then timeStr = format("%dh ago", math.floor(elapsed / 3600))
        else timeStr = format("%dd ago", math.floor(elapsed / 86400))
        end
        yOffset = AddLine(scrollChild, yOffset, (ns.L and ns.L["PROF_INFO_LAST_UPDATE"]) or "Last Updated", ColorText(timeStr, LABEL_COLOR))
    end

    scrollChild:SetHeight(yOffset + PADDING)
end

-- ============================================================================
-- CREATE / SHOW WINDOW
-- ============================================================================

local function CreateInfoFrame()
    if infoFrame then return infoFrame end

    local frame = CreateFrame("Frame", "WarbandNexus_ProfessionInfo", UIParent)
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame:SetMovable(true)

    -- WindowManager: standardized strata/level + ESC + combat hide
    if ns.WindowManager then
        ns.WindowManager:ApplyStrata(frame, ns.WindowManager.PRIORITY.FLOATING)
        ns.WindowManager:Register(frame, ns.WindowManager.PRIORITY.FLOATING)
        ns.WindowManager:InstallESCHandler(frame)
    else
        frame:SetFrameStrata("HIGH")
        frame:SetFrameLevel(150)
    end

    if ApplyVisuals then
        ApplyVisuals(frame, {0.03, 0.03, 0.05, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end

    -- Header
    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", -2, -2)
    header:SetFrameLevel(frame:GetFrameLevel() + 10)
    if ApplyVisuals then
        ApplyVisuals(header, {0.06, 0.06, 0.08, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5})
    end

    -- Combat-safe drag handler
    if ns.WindowManager then
        ns.WindowManager:InstallDragHandler(header, frame)
    else
        header:EnableMouse(true)
        header:RegisterForDrag("LeftButton")
        header:SetScript("OnDragStart", function() frame:StartMoving() end)
        header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    end

    -- Icon
    frame.headerIcon = header:CreateTexture(nil, "ARTWORK")
    frame.headerIcon:SetSize(24, 24)
    frame.headerIcon:SetPoint("LEFT", 12, 0)

    -- Title
    frame.titleText = FontManager:CreateFontString(header, "title", "OVERLAY")
    frame.titleText:SetPoint("LEFT", frame.headerIcon, "RIGHT", 8, 0)
    frame.titleText:SetPoint("RIGHT", header, "RIGHT", -40, 0)
    frame.titleText:SetJustifyH("LEFT")
    frame.titleText:SetTextColor(1, 1, 1)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", -8, 0)
    if ApplyVisuals then
        ApplyVisuals(closeBtn, {0.12, 0.12, 0.14, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(14, 14)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    closeBtn:SetScript("OnEnter", function()
        closeIcon:SetVertexColor(1, 0.2, 0.2)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Scroll frame — leave SCROLLBAR_WIDTH+4 on the right for the scrollbar
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -(HEADER_HEIGHT + 4))
    scrollFrame:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_WIDTH + 4), 4)

    -- Style the scrollbar thumb/track to match addon theme
    if scrollFrame.ScrollBar then
        local bar = scrollFrame.ScrollBar
        if bar.ThumbTexture then
            bar.ThumbTexture:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5)
            bar.ThumbTexture:SetWidth(8)
        end
        if bar.trackBG then
            bar.trackBG:SetColorTexture(0.05, 0.05, 0.07, 0.6)
        end
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(CONTENT_WIDTH + PADDING * 2)
    scrollFrame:SetScrollChild(scrollChild)

    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild

    -- ESC handled by WindowManager (no UISpecialFrames to avoid taint)

    infoFrame = frame
    return frame
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function WarbandNexus:ShowProfessionInfo(charKey, profName, profSlot)
    if not charKey or not profName then return end
    if not self.db or not self.db.global or not self.db.global.characters then return end

    local charData = self.db.global.characters[charKey]
    if not charData then return end

    local frame = CreateInfoFrame()
    if not frame then return end

    -- Update header
    local charName = charData.name or charKey
    local classColor = RAID_CLASS_COLORS[charData.classFile] or { r = 1, g = 1, b = 1 }
    local coloredName = format("|cff%02x%02x%02x%s|r", classColor.r*255, classColor.g*255, classColor.b*255, charName)
    frame.titleText:SetText(coloredName .. " - " .. profName)

    -- Update icon
    if profSlot and profSlot.icon then
        frame.headerIcon:SetTexture(profSlot.icon)
        frame.headerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        frame.headerIcon:Show()
    else
        frame.headerIcon:Hide()
    end

    -- Populate content
    PopulateContent(frame.scrollChild, charData, charKey, profName, profSlot)

    frame:Show()
end
