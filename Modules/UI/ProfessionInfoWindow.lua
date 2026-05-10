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
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager
local ProfessionInfoEvents = {} -- Unique AceEvent identity for this module

local Utilities = ns.Utilities
local issecretvalue = issecretvalue
local function SafeLower(s)
    return Utilities and Utilities.SafeLower and Utilities:SafeLower(s) or ""
end
local COLORS = ns.UI_COLORS or { accent = { 0.5, 0.4, 0.7 }, accentDark = { 0.25, 0.2, 0.35 } }
local ApplyVisuals = ns.UI_ApplyVisuals
local function GetFactory()
    return ns.UI and ns.UI.Factory
end

-- Layout constants
local PADDING = 12
local SCROLLBAR_WIDTH = 22
local HEADER_HEIGHT = 40
local SECTION_GAP = 10
local LINE_HEIGHT = 18
local NODE_LINE_HEIGHT = 16
local LABEL_WIDTH = 132
local DEFAULT_WIDTH = 440
local DEFAULT_HEIGHT = 560
local MIN_WIDTH = 350
local MIN_HEIGHT = 400
local MAX_WIDTH = 600
local MAX_HEIGHT = 900
local CONTENT_WIDTH = DEFAULT_WIDTH - PADDING * 2 - SCROLLBAR_WIDTH  -- Updated dynamically when frame is resized

-- Tree node layout
local TREE_NODE_HEIGHT = 24                               -- each tree node row height
local TREE_NODE_GAP = 2                                   -- gap between rows
local TREE_INDENT = 16                                    -- indentation per tree depth level
local TREE_CONNECTOR_WIDTH = 2                            -- width of tree branch lines
local PROGRESS_BAR_HEIGHT = 12

-- Colors
local LABEL_COLOR = { 0.7, 0.7, 0.7 }
local VALUE_COLOR = { 1, 1, 1 }
local GREEN = { 0.3, 0.9, 0.3 }
local YELLOW = { 1, 0.82, 0 }
local DIM = { 0.45, 0.45, 0.45 }
local NODE_ALLOCATED = { 0.6, 0.85, 1 }
local NODE_UNALLOCATED = { 0.4, 0.4, 0.4 }
local NODE_MAXED_BG = { 0.12, 0.25, 0.12, 0.9 }
local NODE_PARTIAL_BG = { 0.10, 0.18, 0.28, 0.9 }
local NODE_EMPTY_BG = { 0.08, 0.08, 0.10, 0.7 }
local NODE_MAXED_BORDER = { 0.3, 0.9, 0.3, 0.6 }
local NODE_PARTIAL_BORDER = { 0.4, 0.7, 1, 0.5 }
local NODE_EMPTY_BORDER = { 0.25, 0.25, 0.3, 0.4 }

local format = string.format

-- Singleton frame
local infoFrame = nil

-- ============================================================================
-- POSITION / SIZE (db.global.professionInfo)
-- ============================================================================

local function GetProfInfoDB()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return nil end
    if not WarbandNexus.db.global.professionInfo then
        WarbandNexus.db.global.professionInfo = {
            point = "CENTER", relativePoint = "CENTER", x = 0, y = 0,
            width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT,
        }
    end
    return WarbandNexus.db.global.professionInfo
end

local function SaveProfInfoPosition(frame)
    if not frame then return end
    local db = GetProfInfoDB()
    if not db then return end
    if frame:GetNumPoints() < 1 then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    db.point = point
    db.relativePoint = relativePoint
    db.x = x
    db.y = y
    db.width = frame:GetWidth()
    db.height = frame:GetHeight()
end

local function RestoreProfInfoPosition(frame)
    local db = GetProfInfoDB()
    if not db then return end
    frame:ClearAllPoints()
    frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or 0)
    local w = db.width or DEFAULT_WIDTH
    local h = db.height or DEFAULT_HEIGHT
    if w < MIN_WIDTH then w = DEFAULT_WIDTH end
    if h < MIN_HEIGHT then h = DEFAULT_HEIGHT end
    if h > MAX_HEIGHT then h = MAX_HEIGHT end
    if w > MAX_WIDTH then w = MAX_WIDTH end
    frame:SetSize(w, h)
end

local MIDNIGHT_SKILLLINE_IDS = {
    [2906] = true, [2907] = true, [2909] = true, [2910] = true, [2912] = true, [2913] = true,
    [2914] = true, [2915] = true, [2916] = true, [2917] = true, [2918] = true,
}

-- Midnight-only filter (per WN-VERSION-midnight-policy.mdc)
-- Prefer skillLineID matching to avoid locale-dependent name checks.
local function IsMidnightExpansion(name, skillLineID)
    if skillLineID and MIDNIGHT_SKILLLINE_IDS[skillLineID] then
        return true
    end
    return name and type(name) == "string" and not (issecretvalue and issecretvalue(name))
        and name:find("Midnight", 1, true)
end

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

local function NormalizeProfessionKey(name)
    if not name or type(name) ~= "string" then return name end
    if issecretvalue and issecretvalue(name) then return name end
    return name
        :gsub("^Midnight ", "")
        :gsub("^Khaz Algar ", "")
        :gsub("^Dragon Isles ", "")
        :gsub("^Shadowlands ", "")
end

local function ResolveProfessionEquipment(charData, profName)
    if not charData or type(charData.professionEquipment) ~= "table" then return nil end
    local eqByProf = charData.professionEquipment
    local eqKey = NormalizeProfessionKey(profName) or profName
    local eqData = eqByProf[profName] or eqByProf[eqKey]

    if not eqData and (profName or eqKey) then
        for k, v in pairs(eqByProf) do
            if k ~= "_legacy" and type(v) == "table" and (v.tool or v.accessory1 or v.accessory2) then
                local norm = NormalizeProfessionKey(k)
                local kSafe = type(k) == "string" and not (issecretvalue and issecretvalue(k))
                local eqSafe = eqKey and not (issecretvalue and issecretvalue(eqKey))
                if norm == eqKey or (eqSafe and kSafe and k:find(eqKey, 1, true)) then
                    eqData = v
                    break
                end
            end
        end
    end

    return eqData
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
-- TALENT TREE VISUAL HELPERS
-- ============================================================================

-- Create a small progress bar
local function AddProgressBar(scrollChild, yOffset, current, maximum, barColor, indent)
    indent = indent or 0
    local barWidth = CONTENT_WIDTH - indent
    local barX = PADDING + indent

    -- Background
    local bg = scrollChild:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", barX, -yOffset)
    bg:SetSize(barWidth, PROGRESS_BAR_HEIGHT)
    bg:SetColorTexture(0.06, 0.06, 0.08, 1)

    -- Fill
    if maximum and maximum > 0 and current and current > 0 then
        local fill = scrollChild:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", barX, -yOffset)
        local fillW = math.max(1, math.floor(barWidth * math.min(1, current / maximum)))
        fill:SetSize(fillW, PROGRESS_BAR_HEIGHT)
        fill:SetColorTexture(barColor[1], barColor[2], barColor[3], 0.6)
    end

    -- Border lines (top, bottom, left, right)
    local progressBarEdges = {
        { "TOPLEFT", "TOPRIGHT", barWidth, 1, 0, 0 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", barWidth, 1, 0, 0 },
        { "TOPLEFT", "BOTTOMLEFT", 1, PROGRESS_BAR_HEIGHT, 0, 0 },
        { "TOPRIGHT", "BOTTOMRIGHT", 1, PROGRESS_BAR_HEIGHT, 0, 0 },
    }
    for ei = 1, #progressBarEdges do
        local edge = progressBarEdges[ei]
        local line = scrollChild:CreateTexture(nil, "OVERLAY")
        line:SetPoint(edge[1], bg, edge[1], edge[5], edge[6])
        line:SetSize(edge[3], edge[4])
        line:SetColorTexture(1, 1, 1, 0.1)
    end

    -- Text overlay
    local txt = FontManager:CreateFontString(scrollChild, "small", "OVERLAY")
    txt:SetPoint("CENTER", bg, "CENTER", 0, 0)
    txt:SetText(ColorText(tostring(current or 0) .. " / " .. tostring(maximum or 0), VALUE_COLOR))

    return yOffset + PROGRESS_BAR_HEIGHT + 4
end

-- Create a tab header bar with badge
local function AddTabHeader(scrollChild, yOffset, tabName, isUnlocked, spentRanks, totalRanks, allocatedNodes, totalNodes)
    local barX = PADDING + 10
    local barWidth = CONTENT_WIDTH - 10

    -- Background bar
    local bg = scrollChild:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", barX, -yOffset)
    bg:SetSize(barWidth, 24)
    if isUnlocked then
        bg:SetColorTexture(COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 0.7)
    else
        bg:SetColorTexture(0.08, 0.08, 0.10, 0.7)
    end

    -- Tab name
    local name = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
    name:SetPoint("LEFT", bg, "LEFT", 8, 0)
    name:SetWidth(barWidth * 0.5)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetText(ColorText(tabName, isUnlocked and VALUE_COLOR or DIM))

    -- Status badge
    local badge = FontManager:CreateFontString(scrollChild, "small", "OVERLAY")
    badge:SetPoint("RIGHT", bg, "RIGHT", -8, 0)
    badge:SetJustifyH("RIGHT")
    if isUnlocked then
        local summaryStr = ColorText(allocatedNodes .. "/" .. totalNodes, NODE_ALLOCATED)
            .. ColorText(" nodes  ", DIM)
            .. ColorText(spentRanks .. "/" .. totalRanks, NODE_ALLOCATED)
            .. ColorText(" pts", DIM)
        badge:SetText(summaryStr)
    else
        badge:SetText(ColorText((ns.L and ns.L["PROF_INFO_LOCKED"]) or "Locked", DIM))
    end

    -- Bottom border
    local line = scrollChild:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
    line:SetSize(barWidth, 1)
    line:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.3)

    return yOffset + 26
end

-- ============================================================================
-- TREE LAYOUT ENGINE
-- ============================================================================

-- Build a tree structure from flat node list using edges and positions
local function BuildTreeHierarchy(nodes)
    if not nodes or #nodes == 0 then return {} end

    -- Index nodes by nodeID
    local byID = {}
    for i = 1, #nodes do
        local n = nodes[i]
        if n.nodeID then
            byID[n.nodeID] = n
        end
    end

    -- Build parent→children map from edges
    local children = {}    -- parentID → { childNode, ... }
    local hasParent = {}   -- nodeID → true if this node is a child of another
    for i = 1, #nodes do
        local n = nodes[i]
        if n.edges and n.nodeID then
            for e = 1, #n.edges do
                local targetID = n.edges[e]
                if byID[targetID] then
                    if not children[n.nodeID] then children[n.nodeID] = {} end
                    children[n.nodeID][#children[n.nodeID] + 1] = byID[targetID]
                    hasParent[targetID] = true
                end
            end
        end
    end

    -- Roots = nodes with no parent
    local roots = {}
    for i = 1, #nodes do
        local n = nodes[i]
        if n.nodeID and not hasParent[n.nodeID] then
            roots[#roots + 1] = n
        end
    end

    -- If no edges or all nodes are roots, fall back to position-based tiers
    if #roots == #nodes or #roots == 0 then
        return nil -- signal to use tier-based layout
    end

    -- Sort roots by posX
    table.sort(roots, function(a, b) return (a.posX or 0) < (b.posX or 0) end)

    -- Sort children by posX
    for _, childList in pairs(children) do
        table.sort(childList, function(a, b) return (a.posX or 0) < (b.posX or 0) end)
    end

    return roots, children
end

-- Flatten tree into display order with depth info
local function FlattenTree(roots, children, result, depth)
    result = result or {}
    depth = depth or 0
    for i = 1, #roots do
        local node = roots[i]
        result[#result + 1] = { node = node, depth = depth }
        local childList = children and children[node.nodeID]
        if childList then
            FlattenTree(childList, children, result, depth + 1)
        end
    end
    return result
end

-- Build tier-based layout from positions (fallback when no edge data)
local function BuildTierLayout(nodes)
    if not nodes or #nodes == 0 then return {} end

    -- Group by posY into tiers
    local tiers = {}
    local tierKeys = {}
    for i = 1, #nodes do
        local n = nodes[i]
        local y = n.posY or 0
        if not tiers[y] then
            tiers[y] = {}
            tierKeys[#tierKeys + 1] = y
        end
        tiers[y][#tiers[y] + 1] = n
    end

    -- Sort tiers by Y (top to bottom)
    table.sort(tierKeys)

    -- Sort nodes within each tier by X
    for tki = 1, #tierKeys do
        local y = tierKeys[tki]
        table.sort(tiers[y], function(a, b) return (a.posX or 0) < (b.posX or 0) end)
    end

    -- Flatten with depth based on tier index
    local result = {}
    for tierIdx = 1, #tierKeys do
        local y = tierKeys[tierIdx]
        local depth = tierIdx - 1
        local tierNodes = tiers[y]
        for ni = 1, #tierNodes do
            local node = tierNodes[ni]
            result[#result + 1] = { node = node, depth = depth }
        end
    end
    return result
end

-- Draw a single tree node row with branch indicators
local function AddTreeNodeRow(scrollChild, yOffset, node, depth, isLastInGroup, hasChildren)
    local indent = PADDING + 10 + depth * TREE_INDENT
    local rowWidth = CONTENT_WIDTH - 10 - depth * TREE_INDENT
    local currentRank = node.currentRank or 0
    local maxRanks = node.maxRanks or 1
    local isMaxed = currentRank >= maxRanks
    local isAllocated = currentRank > 0

    -- Row background
    local bg = scrollChild:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", indent, -yOffset)
    bg:SetSize(rowWidth, TREE_NODE_HEIGHT)
    if isMaxed then
        bg:SetColorTexture(NODE_MAXED_BG[1], NODE_MAXED_BG[2], NODE_MAXED_BG[3], NODE_MAXED_BG[4])
    elseif isAllocated then
        bg:SetColorTexture(NODE_PARTIAL_BG[1], NODE_PARTIAL_BG[2], NODE_PARTIAL_BG[3], NODE_PARTIAL_BG[4])
    else
        bg:SetColorTexture(NODE_EMPTY_BG[1], NODE_EMPTY_BG[2], NODE_EMPTY_BG[3], NODE_EMPTY_BG[4])
    end

    -- Tree branch connector (for depth > 0)
    if depth > 0 then
        local connectorX = indent - TREE_INDENT + 6
        -- Vertical line
        local vline = scrollChild:CreateTexture(nil, "ARTWORK")
        vline:SetPoint("TOPLEFT", connectorX, -(yOffset - TREE_NODE_GAP))
        vline:SetSize(TREE_CONNECTOR_WIDTH, TREE_NODE_HEIGHT / 2 + TREE_NODE_GAP)
        local connColor = isAllocated and { 0.4, 0.7, 1, 0.4 } or { 0.3, 0.3, 0.35, 0.3 }
        vline:SetColorTexture(connColor[1], connColor[2], connColor[3], connColor[4])

        -- Horizontal line
        local hline = scrollChild:CreateTexture(nil, "ARTWORK")
        hline:SetPoint("TOPLEFT", connectorX, -(yOffset + TREE_NODE_HEIGHT / 2 - 1))
        hline:SetSize(TREE_INDENT - 8, TREE_CONNECTOR_WIDTH)
        hline:SetColorTexture(connColor[1], connColor[2], connColor[3], connColor[4])
    end

    -- Left indicator bar
    local indicator = scrollChild:CreateTexture(nil, "ARTWORK")
    indicator:SetSize(3, TREE_NODE_HEIGHT - 4)
    indicator:SetPoint("LEFT", bg, "LEFT", 2, 0)
    if isMaxed then
        indicator:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.9)
    elseif isAllocated then
        indicator:SetColorTexture(NODE_ALLOCATED[1], NODE_ALLOCATED[2], NODE_ALLOCATED[3], 0.9)
    else
        indicator:SetColorTexture(NODE_UNALLOCATED[1], NODE_UNALLOCATED[2], NODE_UNALLOCATED[3], 0.5)
    end

    -- Node name
    local nameText = FontManager:CreateFontString(scrollChild, "small", "OVERLAY")
    nameText:SetPoint("LEFT", bg, "LEFT", 9, 0)
    nameText:SetWidth(rowWidth - 55)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    local nameColor = isMaxed and VALUE_COLOR or (isAllocated and NODE_ALLOCATED or DIM)
    nameText:SetText(ColorText(node.name or "?", nameColor))

    -- Rank badge
    local rankText = FontManager:CreateFontString(scrollChild, "small", "OVERLAY")
    rankText:SetPoint("RIGHT", bg, "RIGHT", -6, 0)
    rankText:SetJustifyH("RIGHT")
    local rankColor = isMaxed and GREEN or (isAllocated and YELLOW or DIM)
    rankText:SetText(ColorText(currentRank .. "/" .. maxRanks, rankColor))

    -- Subtle border
    local borderColor = isMaxed and NODE_MAXED_BORDER or (isAllocated and NODE_PARTIAL_BORDER or NODE_EMPTY_BORDER)
    local treeRowEdges = {
        { "TOPLEFT", rowWidth, 1 },
        { "BOTTOMLEFT", rowWidth, 1 },
        { "TOPLEFT", 1, TREE_NODE_HEIGHT },
    }
    for ei = 1, #treeRowEdges do
        local edge = treeRowEdges[ei]
        local bline = scrollChild:CreateTexture(nil, "OVERLAY")
        bline:SetPoint(edge[1], bg, edge[1], 0, 0)
        bline:SetSize(edge[2], edge[3])
        bline:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end
    -- Right border
    local rbline = scrollChild:CreateTexture(nil, "OVERLAY")
    rbline:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
    rbline:SetSize(1, TREE_NODE_HEIGHT)
    rbline:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])

    return yOffset + TREE_NODE_HEIGHT + TREE_NODE_GAP
end

-- Render the full talent tree for a spec tab
local function AddTalentTree(scrollChild, yOffset, nodes)
    if not nodes or #nodes == 0 then return yOffset end

    -- Try to build tree hierarchy from edges
    local roots, childrenMap = BuildTreeHierarchy(nodes)
    local displayList

    if roots and childrenMap then
        -- Edge-based tree
        displayList = FlattenTree(roots, childrenMap)
    else
        -- Fallback: position-based tier layout
        displayList = BuildTierLayout(nodes)
    end

    if not displayList or #displayList == 0 then
        -- Final fallback: flat alphabetical list
        displayList = {}
        local sorted = {}
        for i = 1, #nodes do sorted[#sorted + 1] = nodes[i] end
        table.sort(sorted, function(a, b) return SafeLower(a.name) < SafeLower(b.name) end)
        for i = 1, #sorted do
            displayList[i] = { node = sorted[i], depth = 0 }
        end
    end

    -- Determine which entries have children (for visual hints)
    local hasChildAtDepth = {}
    for i = 1, #displayList do
        local nextDepth = displayList[i + 1] and displayList[i + 1].depth or 0
        hasChildAtDepth[i] = nextDepth > displayList[i].depth
    end

    -- Render each node
    for i = 1, #displayList do
        local entry = displayList[i]
        local isLast = not displayList[i + 1] or displayList[i + 1].depth <= entry.depth
        yOffset = AddTreeNodeRow(scrollChild, yOffset, entry.node, entry.depth, isLast, hasChildAtDepth[i])
    end

    return yOffset
end

-- ============================================================================
-- POPULATE WINDOW CONTENT
-- ============================================================================

local function PopulateContent(scrollChild, charData, charKey, profName, profSlot)
    -- Update content width from current frame size (for resizable window)
    local frame = scrollChild:GetParent() and scrollChild:GetParent():GetParent()
    if frame and frame.GetWidth then
        local w = frame:GetWidth()
        if w and w > 0 then
            CONTENT_WIDTH = w - PADDING * 2 - SCROLLBAR_WIDTH
        end
    end
    scrollChild:SetWidth(CONTENT_WIDTH + PADDING * 2)

    -- Clear previous content
    local bin = ns.UI_RecycleBin
    local regions = { scrollChild:GetRegions() }
    for ri = 1, #regions do
        local region = regions[ri]
        region:Hide()
        if bin then region:SetParent(bin) else region:SetParent(nil) end
    end
    local children = { scrollChild:GetChildren() }
    for ci = 1, #children do
        local child = children[ci]
        child:Hide()
        if bin then child:SetParent(bin) else child:SetParent(nil) end
    end

    local yOffset = PADDING

    -- Find relevant skillLineIDs for Midnight only
    local relevantSkillLines = {}
    local midnightExpansions = {}
    if charData.professionExpansions and charData.professionExpansions[profName] then
        local profExpansions = charData.professionExpansions[profName]
        for exi = 1, #profExpansions do
            local exp = profExpansions[exi]
            if IsMidnightExpansion(exp.name, exp.skillLineID) then
                if exp.skillLineID then
                    relevantSkillLines[#relevantSkillLines + 1] = exp.skillLineID
                end
                midnightExpansions[#midnightExpansions + 1] = exp
            end
        end
    end

    -- Check data availability (Midnight only)
    local hasExpansions = #midnightExpansions > 0
    local hasConcentration = false
    local hasKnowledge = false
    local hasRecipes = false
    local hasEquipment = false
    local hasCooldowns = false

    -- Check data availability
    if charData.concentration then
        for sli = 1, #relevantSkillLines do
            local slID = relevantSkillLines[sli]
            if charData.concentration[slID] then hasConcentration = true; break end
        end
    end
    if charData.knowledgeData then
        for sli = 1, #relevantSkillLines do
            local slID = relevantSkillLines[sli]
            if charData.knowledgeData[slID] then hasKnowledge = true; break end
        end
    end
    if charData.recipes then
        for sli = 1, #relevantSkillLines do
            local slID = relevantSkillLines[sli]
            if charData.recipes[slID] then hasRecipes = true; break end
        end
    end

    local eqData = ResolveProfessionEquipment(charData, profName)
    hasEquipment = eqData and (eqData.tool or eqData.accessory1 or eqData.accessory2) or false

    if charData.professionCooldowns then
        for sli = 1, #relevantSkillLines do
            local slID = relevantSkillLines[sli]
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

    -- ===== EXPANSION SKILLS (Midnight only) =====
    if hasExpansions then
        yOffset = AddSectionHeader(scrollChild, yOffset, (ns.L and ns.L["PROF_INFO_SKILLS"]) or "Expansion Skills")
        for exi = 1, #midnightExpansions do
            local exp = midnightExpansions[exi]
            local cur = exp.skillLevel or 0
            local mx = exp.maxSkillLevel or 0
            local color = ProgressColor(cur, mx)
            yOffset = AddLine(scrollChild, yOffset, exp.name or "?", ValueMax(cur, mx, color))
        end
    end

    -- ===== CONCENTRATION =====
    if hasConcentration then
        yOffset = AddSectionHeader(scrollChild, yOffset, (ns.L and ns.L["CONCENTRATION"]) or "Concentration")
        for sli = 1, #relevantSkillLines do
            local slID = relevantSkillLines[sli]
            local concData = charData.concentration[slID]
            if concData and concData.max and concData.max > 0 then
                local current = concData.current or 0
                if WarbandNexus.GetEstimatedConcentration then
                    local estOk, estVal = pcall(WarbandNexus.GetEstimatedConcentration, WarbandNexus, concData)
                    if estOk and type(estVal) == "number" then current = estVal end
                end
                local concMax = concData.max or 0
                local color = ProgressColor(current, concMax)
                local expLabel = concData.expansionName or concData.professionName or ("SkillLine " .. slID)
                yOffset = AddLine(scrollChild, yOffset, expLabel, ValueMax(current, concMax, color))

                -- Recharge time
                if current < concMax and WarbandNexus.GetConcentrationTimeToFull then
                    local tsOk, ts = pcall(WarbandNexus.GetConcentrationTimeToFull, WarbandNexus, concData)
                    if tsOk and ts and ts ~= "" and ts ~= "Full" then
                        yOffset = AddLine(scrollChild, yOffset, (ns.L and ns.L["RECHARGE"]) or "Recharge", ColorText(ts, YELLOW), 10)
                    end
                end
            end
        end
    end

    -- ===== KNOWLEDGE & TALENT TREES =====
    if hasKnowledge then
        yOffset = AddSectionHeader(scrollChild, yOffset, (ns.L and ns.L["KNOWLEDGE"]) or "Knowledge")
        for sli = 1, #relevantSkillLines do
            local slID = relevantSkillLines[sli]
            local kd = charData.knowledgeData[slID]
            if kd then
                local spent = kd.spentPoints or 0
                local unspent = kd.unspentPoints or 0
                local maxPts = kd.maxPoints or 0
                local current = spent + unspent
                local label = kd.expansionName or kd.professionName or ("SkillLine " .. slID)

                -- Knowledge progress bar
                local barColor = ProgressColor(current, maxPts)
                yOffset = AddLine(scrollChild, yOffset, label, ValueMax(current, maxPts, barColor))
                yOffset = AddProgressBar(scrollChild, yOffset, current, maxPts, barColor, 10)

                if unspent > 0 then
                    yOffset = AddLine(scrollChild, yOffset, (ns.L and ns.L["UNSPENT_POINTS"]) or "Unspent", ColorText(unspent, YELLOW), 10)
                end

                -- Specialization Tabs: only tab-level summary (spent/total pts), no inner node list
                if kd.specTabs and #kd.specTabs > 0 then
                    yOffset = yOffset + 4
                    for sti = 1, #kd.specTabs do
                        local tab = kd.specTabs[sti]
                        local stateTxt = tab.state or "?"
                        local stateLower = (type(stateTxt) == "string" and not (issecretvalue and issecretvalue(stateTxt)))
                            and stateTxt:lower() or ""
                        local isUnlocked = (stateTxt == "1" or stateLower == "unlocked")
                        local allocatedCount, totalRanks, spentRanks, totalNodes = 0, 0, 0, 0
                        if tab.nodes then
                            for ni = 1, #tab.nodes do
                                local node = tab.nodes[ni]
                                if node then
                                    totalRanks = totalRanks + (node.maxRanks or 0)
                                    spentRanks = spentRanks + (node.currentRank or 0)
                                    if (node.currentRank or 0) > 0 then
                                        allocatedCount = allocatedCount + 1
                                    end
                                    totalNodes = totalNodes + 1
                                end
                            end
                        end

                        -- Tab header bar with summary (e.g. Alchemical Mastery: 15/30 pts)
                        yOffset = AddTabHeader(scrollChild, yOffset, tab.name or "?",
                            isUnlocked, spentRanks, totalRanks, allocatedCount, totalNodes)

                        yOffset = yOffset + 2
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
        local equipSlotKeys = { "tool", "accessory1", "accessory2" }
        for ski = 1, #equipSlotKeys do
            local slotKey = equipSlotKeys[ski]
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
        for sli = 1, #relevantSkillLines do
            local slID = relevantSkillLines[sli]
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
                        return SafeLower(a.name) < SafeLower(b.name)
                    end)

                    for ri = 1, #sorted do
                        local recipe = sorted[ri]
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
    for sli = 1, #relevantSkillLines do
        local slID = relevantSkillLines[sli]
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
            for ski = 1, #sourceKeys do
                local key = sourceKeys[ski]
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
        for sli = 1, #relevantSkillLines do
            local slID = relevantSkillLines[sli]
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
    local factory = GetFactory()
    local scrollFrame = scrollChild:GetParent()
    if factory and factory.UpdateScrollBarVisibility and scrollFrame then
        factory:UpdateScrollBarVisibility(scrollFrame)
    end
end

-- ============================================================================
-- CREATE / SHOW WINDOW
-- ============================================================================

local function CreateInfoFrame()
    if infoFrame then return infoFrame end

    local frame = CreateFrame("Frame", "WarbandNexus_ProfessionInfo", UIParent)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    if frame.SetMinResize then
        frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    end
    if frame.SetMaxResize then
        frame:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
    end
    frame:SetClampedToScreen(true)
    RestoreProfInfoPosition(frame)

    -- WindowManager: standardized strata/level + ESC + combat hide
    if ns.WindowManager then
        ns.WindowManager:ApplyStrata(frame, ns.WindowManager.PRIORITY.FLOATING)
        ns.WindowManager:Register(frame, ns.WindowManager.PRIORITY.FLOATING)
        ns.WindowManager:InstallESCHandler(frame)
    else
        frame:SetFrameStrata("HIGH")
        frame:SetFrameLevel(120)
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

    -- Combat-safe, scale-correct drag handler
    header:EnableMouse(true)
    if ns.WindowManager and ns.WindowManager.InstallDragHandler then
        ns.WindowManager:InstallDragHandler(header, frame, function()
            SaveProfInfoPosition(frame)
        end)
    else
        header:RegisterForDrag("LeftButton")
        header:SetScript("OnDragStart", function() frame:StartMoving() end)
        header:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            SaveProfInfoPosition(frame)
        end)
    end

    -- Icon
    frame.headerIcon = header:CreateTexture(nil, "ARTWORK")
    frame.headerIcon:SetSize(24, 24)
    frame.headerIcon:SetPoint("LEFT", 12, 0)

    -- Title
    frame.titleText = FontManager:CreateFontString(header, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
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

    local factory = GetFactory()
    local scrollFrame
    if factory and factory.CreateScrollFrame then
        scrollFrame = factory:CreateScrollFrame(frame, "UIPanelScrollFrameTemplate", true)
    else
        scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    end
    scrollFrame:SetPoint("TOPLEFT", 4, -(HEADER_HEIGHT + 4))
    scrollFrame:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_WIDTH + 4), 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(CONTENT_WIDTH + PADDING * 2)
    scrollFrame:SetScrollChild(scrollChild)

    if factory and factory.CreateScrollBarColumn and factory.PositionScrollBarInContainer and scrollFrame.ScrollBar then
        local scrollBarColumn = factory:CreateScrollBarColumn(frame, SCROLLBAR_WIDTH, HEADER_HEIGHT + 4, 4)
        if scrollBarColumn then
            factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
        end
    end

    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild

    -- Resize grip (bottom-right)
    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT", -2, 2)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:EnableMouse(true)
    resizer:SetFrameStrata(frame:GetFrameStrata())
    resizer:SetFrameLevel(frame:GetFrameLevel() + 50)
    resizer:SetScript("OnMouseDown", function()
        if not InCombatLockdown() then frame:StartSizing("BOTTOMRIGHT") end
    end)
    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SaveProfInfoPosition(frame)
        if frame.scrollChild and frame._charData and frame._profName then
            PopulateContent(frame.scrollChild, frame._charData, frame._charKey, frame._profName, frame._profSlot)
        end
    end)

    frame:SetScript("OnSizeChanged", function()
        if frame.scrollFrame and frame.scrollChild then
            frame.scrollChild:SetWidth(frame.scrollFrame:GetWidth())
        end
    end)

    frame:SetScript("OnShow", function()
        if frame.scrollFrame and frame.scrollChild then
            frame.scrollChild:SetWidth(frame.scrollFrame:GetWidth())
        end
    end)

    frame:SetScript("OnHide", function()
        SaveProfInfoPosition(frame)
    end)

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

    -- Store for resize-triggered repopulate
    frame._charData = charData
    frame._charKey = charKey
    frame._profName = profName
    frame._profSlot = profSlot

    -- Populate content
    PopulateContent(frame.scrollChild, charData, charKey, profName, profSlot)

    frame:Show()
end

local function RefreshVisibleProfessionInfo(updatedCharKey)
    local frame = infoFrame
    if not frame or not frame:IsShown() then return end
    if not frame._charKey or not frame._profName then return end
    if updatedCharKey and updatedCharKey ~= frame._charKey then return end
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.characters then return end

    local latestCharData = WarbandNexus.db.global.characters[frame._charKey]
    if not latestCharData then return end

    frame._charData = latestCharData
    PopulateContent(frame.scrollChild, latestCharData, frame._charKey, frame._profName, frame._profSlot)
end

if WarbandNexus and WarbandNexus.RegisterMessage then
    WarbandNexus.RegisterMessage(ProfessionInfoEvents, E.PROFESSION_EQUIPMENT_UPDATED, function(_, charKey)
        RefreshVisibleProfessionInfo(charKey)
    end)
    WarbandNexus.RegisterMessage(ProfessionInfoEvents, E.PROFESSION_DATA_UPDATED, function(_, charKey)
        RefreshVisibleProfessionInfo(charKey)
    end)
end
