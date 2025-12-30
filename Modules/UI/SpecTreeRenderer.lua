--[[
    Warband Nexus - Spec Tree Renderer
    Visual rendering of profession specialization talent trees
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local CreateCard = ns.UI_CreateCard

-- Node visual constants
local NODE_SIZE = 36
local NODE_SPACING_X = 60
local NODE_SPACING_Y = 60
local TREE_PADDING = 40

-- Node colors
local NODE_COLORS = {
    available = {0.3, 0.7, 1.0, 1.0},      -- Blue
    purchased = {0.2, 0.9, 0.3, 1.0},      -- Green
    maxed = {1.0, 0.8, 0.2, 1.0},          -- Gold
    unavailable = {0.3, 0.3, 0.3, 0.6},    -- Gray
    locked = {0.5, 0.2, 0.2, 0.8}          -- Dark red
}

--[[
    Create a spec tree canvas with scroll capability
    @param parent Frame - Parent frame
    @param specData table - Specialization data
    @param charKey string - Character key for state tracking
    @param profName string - Profession name
    @return Frame - The tree canvas frame
]]
function WarbandNexus:CreateSpecTreeCanvas(parent, specData, charKey, profName)
    if not specData or not specData.nodes then
        return CreateFrame("Frame", nil, parent)
    end
    
    -- Main container
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(parent:GetWidth() - 20, 450)
    
    -- Background
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    container:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    container:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    titleBar:SetHeight(30)
    titleBar:SetPoint("TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", -4, -4)
    titleBar:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
    titleBar:SetBackdropColor(0.1, 0.1, 0.15, 1)
    
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 10, 0)
    titleText:SetText(specData.name or "Specialization Tree")
    titleText:SetTextColor(1, 0.8, 0.2)
    
    -- Knowledge points display
    local knowledgeText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    knowledgeText:SetPoint("RIGHT", -10, 0)
    knowledgeText:SetText(string.format("Knowledge: %d / %d", 
        specData.knowledgeSpent or 0, 
        specData.knowledgeMax or 0))
    knowledgeText:SetTextColor(0.3, 0.9, 0.3)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", knowledgeText, "LEFT", -10, 0)
    closeBtn:SetNormalFontObject("GameFontNormal")
    closeBtn:SetText("×")
    closeBtn:GetFontString():SetTextColor(0.8, 0.3, 0.3)
    closeBtn:SetScript("OnClick", function()
        container:Hide()
        -- Update expand state
        local expandKey = charKey .. "-" .. profName .. "-tree"
        if ns.expandedSpecTrees then
            ns.expandedSpecTrees[expandKey] = false
        end
        WarbandNexus:RefreshUI()
    end)
    closeBtn:SetScript("OnEnter", function(self) 
        self:GetFontString():SetTextColor(1, 0.5, 0.5) 
    end)
    closeBtn:SetScript("OnLeave", function(self) 
        self:GetFontString():SetTextColor(0.8, 0.3, 0.3) 
    end)
    
    -- Scroll frame for tree
    local scrollFrame = CreateFrame("ScrollFrame", nil, container)
    scrollFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    
    -- Scroll child (canvas)
    local canvas = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(canvas)
    
    -- Calculate canvas size based on node positions
    local minX, maxX = 9999, 0
    local minY, maxY = 9999, 0
    
    for _, node in ipairs(specData.nodes) do
        if node.posX then
            minX = math.min(minX, node.posX)
            maxX = math.max(maxX, node.posX)
        end
        if node.posY then
            minY = math.min(minY, node.posY)
            maxY = math.max(maxY, node.posY)
        end
    end
    
    local canvasWidth = math.max(600, (maxX - minX) * 2 + TREE_PADDING * 2)
    local canvasHeight = math.max(400, (maxY - minY) * 2 + TREE_PADDING * 2)
    canvas:SetSize(canvasWidth, canvasHeight)
    
    -- Store nodes for connection drawing
    canvas.nodeFrames = {}
    
    -- Render nodes
    for _, nodeData in ipairs(specData.nodes) do
        local nodeFrame = self:CreateSpecNode(canvas, nodeData, canvasWidth, canvasHeight)
        if nodeFrame then
            table.insert(canvas.nodeFrames, {frame = nodeFrame, data = nodeData})
        end
    end
    
    -- Draw connections after all nodes are created
    self:DrawNodeConnections(canvas)
    
    return container
end

--[[
    Create a single spec tree node
    @param parent Frame - Parent canvas
    @param nodeData table - Node data
    @param canvasWidth number - Canvas width for positioning
    @param canvasHeight number - Canvas height for positioning
    @return Frame - The node frame
]]
function WarbandNexus:CreateSpecNode(parent, nodeData, canvasWidth, canvasHeight)
    if not nodeData or not nodeData.posX or not nodeData.posY then
        return nil
    end
    
    -- Normalize position to canvas
    local x = (nodeData.posX * 2) + TREE_PADDING
    local y = (nodeData.posY * 2) + TREE_PADDING
    
    -- Create node frame
    local node = CreateFrame("Button", nil, parent, "BackdropTemplate")
    node:SetSize(NODE_SIZE, NODE_SIZE)
    node:SetPoint("TOPLEFT", x - NODE_SIZE/2, -y + NODE_SIZE/2)
    
    -- Determine node color based on state
    local color = NODE_COLORS.unavailable
    if nodeData.currentRank >= nodeData.maxRank then
        color = NODE_COLORS.maxed
    elseif nodeData.currentRank > 0 then
        color = NODE_COLORS.purchased
    elseif nodeData.isAvailable then
        color = NODE_COLORS.available
    end
    
    -- Node background
    node:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    node:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    node:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
    
    -- Icon
    local icon = node:CreateTexture(nil, "ARTWORK")
    icon:SetSize(NODE_SIZE - 6, NODE_SIZE - 6)
    icon:SetPoint("CENTER")
    
    if nodeData.icon then
        icon:SetTexture(nodeData.icon)
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    
    -- Rank badge (bottom right)
    if nodeData.maxRank > 1 then
        local rankBadge = node:CreateTexture(nil, "OVERLAY")
        rankBadge:SetSize(16, 16)
        rankBadge:SetPoint("BOTTOMRIGHT", 2, -2)
        rankBadge:SetColorTexture(0, 0, 0, 0.8)
        
        local rankText = node:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rankText:SetPoint("CENTER", rankBadge, "CENTER", 0, 0)
        rankText:SetText(string.format("%d/%d", nodeData.currentRank, nodeData.maxRank))
        
        if nodeData.currentRank >= nodeData.maxRank then
            rankText:SetTextColor(1, 0.8, 0.2)
        elseif nodeData.currentRank > 0 then
            rankText:SetTextColor(0.2, 0.9, 0.3)
        else
            rankText:SetTextColor(0.6, 0.6, 0.6)
        end
    end
    
    -- Tooltip
    node:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(nodeData.name or "Unknown", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Rank:", string.format("%d / %d", 
            nodeData.currentRank, nodeData.maxRank), nil, nil, nil, 1, 1, 1)
        
        if nodeData.currentRank >= nodeData.maxRank then
            GameTooltip:AddLine("|cff00ff00Maxed|r", 0, 1, 0)
        elseif nodeData.currentRank > 0 then
            GameTooltip:AddLine("|cffffff00In Progress|r", 1, 1, 0)
        elseif nodeData.isAvailable then
            GameTooltip:AddLine("|cff00ccffAvailable|r", 0, 0.8, 1)
        else
            GameTooltip:AddLine("|cffff6600Locked|r", 1, 0.4, 0)
        end
        
        GameTooltip:Show()
    end)
    node:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Store position for connection drawing
    node.centerX = x
    node.centerY = y
    node.nodeData = nodeData
    
    return node
end

--[[
    Draw connection lines between nodes
    @param canvas Frame - The canvas containing nodes
]]
function WarbandNexus:DrawNodeConnections(canvas)
    if not canvas.nodeFrames or #canvas.nodeFrames == 0 then
        return
    end
    
    -- Create a texture layer for lines
    local lineLayer = canvas:CreateTexture(nil, "BACKGROUND")
    lineLayer:SetAllPoints()
    lineLayer:SetColorTexture(0, 0, 0, 0) -- Transparent base
    
    -- For each node, draw lines to parent nodes
    for _, nodeInfo in ipairs(canvas.nodeFrames) do
        local node = nodeInfo.frame
        local data = nodeInfo.data
        
        if data.parentNodes and #data.parentNodes > 0 then
            -- Find parent node frames
            for _, parentInfo in ipairs(data.parentNodes) do
                -- Draw line (simplified - just a texture line)
                local line = canvas:CreateTexture(nil, "BACKGROUND")
                line:SetColorTexture(0.3, 0.3, 0.4, 0.5)
                line:SetSize(2, 20) -- Simplified vertical line
                line:SetPoint("TOP", node, "TOP", 0, 10)
            end
        end
    end
end

-- Export to namespace
ns.SpecTreeRenderer = {
    CreateSpecTreeCanvas = function(...) return WarbandNexus:CreateSpecTreeCanvas(...) end,
    CreateSpecNode = function(...) return WarbandNexus:CreateSpecNode(...) end,
    DrawNodeConnections = function(...) return WarbandNexus:DrawNodeConnections(...) end,
}

