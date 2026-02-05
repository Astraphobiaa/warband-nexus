--[[
    Warband Nexus - Tooltip Service Module
    Central tooltip management system
    
    Architecture:
    - Single reusable tooltip frame (lazy init)
    - Event-driven show/hide
    - Multiple tooltip types (custom, item, currency, hybrid)
    - Auto-hide on combat/world transitions
    
    API:
    WarbandNexus.Tooltip:Show(frame, data)
    WarbandNexus.Tooltip:Hide()
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

-- Singleton tooltip frame (lazy initialized)
local tooltipFrame = nil
local isVisible = false
local currentAnchor = nil
local isInitialized = false

-- Event names
local TOOLTIP_SHOW = "WN_TOOLTIP_SHOW"
local TOOLTIP_HIDE = "WN_TOOLTIP_HIDE"

-- ============================================================================
-- TOOLTIP SERVICE
-- ============================================================================

local TooltipService = {}

--[[
    Initialize tooltip service
    Creates the singleton frame and registers safety events
]]
function TooltipService:Initialize()
    if isInitialized then return end
    
    -- Lazy init: Create frame when first needed
    -- This is called explicitly from Core.lua
    self:Debug("TooltipService initialized")
    isInitialized = true
    
    -- Register safety events
    self:RegisterSafetyEvents()
end

--[[
    Get or create tooltip frame (lazy init)
]]
local function GetTooltipFrame()
    if not tooltipFrame and ns.UI and ns.UI.TooltipFactory then
        tooltipFrame = ns.UI.TooltipFactory:CreateTooltipFrame()
    end
    return tooltipFrame
end

--[[
    Validate tooltip data structure
    @param data table - Tooltip data
    @return boolean - Valid or not
]]
function TooltipService:ValidateData(data)
    if not data or type(data) ~= "table" then
        return false
    end
    
    -- Type is required
    if not data.type then
        return false
    end
    
    -- Validate based on type
    if data.type == "custom" then
        return data.lines ~= nil
    elseif data.type == "item" then
        return data.itemID ~= nil
    elseif data.type == "currency" then
        return data.currencyID ~= nil
    elseif data.type == "hybrid" then
        return (data.itemID or data.currencyID) and data.lines
    end
    
    return false
end

--[[
    Show tooltip
    @param anchorFrame Frame - Frame to anchor to
    @param data table - Tooltip data structure
]]
function TooltipService:Show(anchorFrame, data)
    local frame = GetTooltipFrame()
    if not frame or not anchorFrame or not data then 
        return 
    end
    
    -- Validate data
    if not self:ValidateData(data) then
        self:Debug("Invalid tooltip data")
        return
    end
    
    -- Clear previous content
    frame:Clear()
    
    -- Render based on type
    if data.type == "custom" then
        self:RenderCustomTooltip(frame, data)
    elseif data.type == "item" then
        self:RenderItemTooltip(frame, data)
    elseif data.type == "currency" then
        self:RenderCurrencyTooltip(frame, data)
    elseif data.type == "hybrid" then
        self:RenderHybridTooltip(frame, data)
    end
    
    -- Position and show
    self:PositionTooltip(frame, anchorFrame, data.anchor or "ANCHOR_RIGHT")
    frame:Show()
    
    currentAnchor = anchorFrame
    isVisible = true
    
    -- Fire event (if AceEvent available)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(TOOLTIP_SHOW, data)
    end
end

--[[
    Hide tooltip
]]
function TooltipService:Hide()
    local frame = GetTooltipFrame()
    if not frame or not isVisible then 
        return 
    end
    
    frame:Clear()
    frame:Hide()
    
    currentAnchor = nil
    isVisible = false
    
    -- Fire event
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(TOOLTIP_HIDE)
    end
end

-- ============================================================================
-- RENDERING METHODS
-- ============================================================================

--[[
    Render custom tooltip with structured data
    @param frame Frame - Tooltip frame
    @param data table - Tooltip data
]]
function TooltipService:RenderCustomTooltip(frame, data)
    -- Add title if present (handle separately from regular lines)
    local hasTitleLine = false
    if data.title then
        -- Create and show title line
        local titleLine = frame:GetOrCreateTitleLine()
        titleLine:SetText(data.title)
        titleLine:SetTextColor(1, 0.82, 0)
        titleLine:Show()
        hasTitleLine = true
        
        -- Don't add to lines array - title is positioned separately
        frame:AddSpacer(8)  -- Spacer after title
    end
    
    -- Process lines
    if data.lines then
        for _, line in ipairs(data.lines) do
            if line.type == "spacer" then
                frame:AddSpacer(line.height or 8)
            elseif line.left and line.right then
                -- Double line (left + right)
                local leftColor = line.leftColor or {1, 1, 1}
                local rightColor = line.rightColor or {1, 1, 1}
                frame:AddDoubleLine(
                    line.left, line.right,
                    leftColor[1], leftColor[2], leftColor[3],
                    rightColor[1], rightColor[2], rightColor[3]
                )
            elseif line.left then
                -- Single line from left field (for convenience)
                local leftColor = line.leftColor or {1, 1, 1}
                frame:AddLine(line.left, leftColor[1], leftColor[2], leftColor[3], line.wrap or false)
            elseif line.text then
                -- Single line from text field
                local color = line.color or {1, 1, 1}
                frame:AddLine(line.text, color[1], color[2], color[3], line.wrap or false)
            end
        end
    end
end

--[[
    Render item tooltip (Blizzard data + custom additions)
    @param frame Frame - Tooltip frame
    @param data table - Tooltip data
]]
function TooltipService:RenderItemTooltip(frame, data)
    -- Use GameTooltip to get item data, then extract and display
    -- This is a hybrid approach: use Blizzard's data but our frame
    
    local itemID = data.itemID
    if not itemID then return end
    
    -- Get item info
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, 
          itemStackCount, itemEquipLoc, itemTexture = C_Item.GetItemInfo(itemID)
    
    if itemName then
        -- Quality color
        local r, g, b = 1, 1, 1
        if itemQuality then
            local color = ITEM_QUALITY_COLORS[itemQuality]
            if color then
                r, g, b = color.r, color.g, color.b
            end
        end
        
        -- Item name with quality color
        frame:AddLine(itemName, r, g, b, false)
        
        -- Item type/subtype
        if itemType then
            local typeText = itemType
            if itemSubType and itemSubType ~= "" then
                typeText = itemSubType
            end
            frame:AddLine(typeText, 1, 1, 1, false)
        end
        
        -- Item level
        if itemLevel and itemLevel > 0 then
            frame:AddLine("Item Level " .. itemLevel, 1, 0.82, 0, false)
        end
    else
        -- Fallback if item not loaded
        frame:AddLine("Item #" .. itemID, 1, 1, 1, false)
        frame:AddLine("Loading...", 0.7, 0.7, 0.7, false)
    end
    
    -- Add custom lines if provided
    if data.additionalLines then
        frame:AddSpacer(8)
        for _, line in ipairs(data.additionalLines) do
            if line.type == "spacer" then
                frame:AddSpacer(line.height or 8)
            elseif line.text then
                local color = line.color or {0.6, 0.4, 0.8}
                frame:AddLine(line.text, color[1], color[2], color[3], line.wrap or false)
            end
        end
    end
end

--[[
    Render currency tooltip (Blizzard data + custom additions)
    @param frame Frame - Tooltip frame
    @param data table - Tooltip data
]]
function TooltipService:RenderCurrencyTooltip(frame, data)
    local currencyID = data.currencyID
    if not currencyID or not C_CurrencyInfo then return end
    
    -- Get currency info
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info then return end
    
    -- CRITICAL: Add currency icon before title
    local titleLine = frame:GetOrCreateTitleLine()
    if info.iconFileID then
        titleLine:SetFormattedText("|T%d:16:16:0:0:64:64:4:60:4:60|t %s", info.iconFileID, info.name)
    else
        titleLine:SetText(info.name)
    end
    titleLine:SetTextColor(1, 0.82, 0)  -- Gold/Yellow (same as Reputation)
    titleLine:Show()
    frame:AddSpacer(8)
    
    -- Description (WHITE)
    if info.description and info.description ~= "" then
        frame:AddLine(info.description, 1, 1, 1, true)  -- White instead of 0.8, 0.8, 0.8
        frame:AddSpacer(8)
    end
    
    -- ===== CROSS-CHARACTER QUANTITIES =====
    -- Show how much this currency exists on all characters
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.global then
        local currencyDB = WarbandNexus.db.global.currencyData
        if currencyDB and currencyDB.currencies then
            local charQuantities = {}
            local totalQuantity = 0
            local totalMaxQuantity = 0
            local hasMaxQuantity = false
            local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
            
            -- Collect quantities from all characters
            for charKey, charCurrencies in pairs(currencyDB.currencies) do
                if charCurrencies[currencyID] then
                    local quantity = charCurrencies[currencyID].quantity or 0
                    local maxQuantity = charCurrencies[currencyID].maxQuantity or 0
                    
                    if quantity > 0 then
                        -- Get character data for class color
                        local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
                        local classFile = charData and charData.class or nil
                        
                        table.insert(charQuantities, {
                            charKey = charKey,
                            quantity = quantity,
                            maxQuantity = maxQuantity,
                            isCurrent = (charKey == currentCharKey),
                            classFile = classFile
                        })
                        totalQuantity = totalQuantity + quantity
                        
                        -- Track if any character has maxQuantity
                        if maxQuantity and maxQuantity > 0 then
                            hasMaxQuantity = true
                            totalMaxQuantity = totalMaxQuantity + maxQuantity
                        end
                    end
                end
            end
            
            -- Sort: Current character first, then by quantity descending
            table.sort(charQuantities, function(a, b)
                if a.isCurrent then return true end
                if b.isCurrent then return false end
                return a.quantity > b.quantity
            end)
            
            -- Show character breakdown (REPUTATION STYLE)
            if #charQuantities > 0 then
                -- Header: "Character Currencies:" (GOLD/YELLOW)
                frame:AddLine("Character Currencies:", 1, 0.82, 0, false)  -- Gold (same as title)
                
                for _, charEntry in ipairs(charQuantities) do
                    -- Parse character name
                    local charName = charEntry.charKey:match("^([^%-]+)") or charEntry.charKey
                    
                    -- Get class color for character name
                    local classColor = {0.7, 0.7, 0.7}  -- Default gray
                    if charEntry.classFile then
                        local classColorObj = C_ClassColor and C_ClassColor.GetClassColor(charEntry.classFile)
                        if classColorObj then
                            classColor = {classColorObj.r, classColorObj.g, classColorObj.b}
                        end
                    end
                    
                    -- Marker for current character
                    local marker = charEntry.isCurrent and " (You)" or ""
                    
                    -- Format amount with FormatNumber
                    local FormatNumber = ns.UI_FormatNumber or function(n) return tostring(n) end
                    local amountText
                    if hasMaxQuantity and charEntry.maxQuantity and charEntry.maxQuantity > 0 then
                        -- Show X/Y format if cap exists
                        amountText = string.format("%s / %s", 
                            FormatNumber(charEntry.quantity), 
                            FormatNumber(charEntry.maxQuantity))
                    else
                        -- Just show quantity
                        amountText = FormatNumber(charEntry.quantity)
                    end
                    
                    -- Format: CharName (You):        Amount (white)
                    -- Use AddDoubleLine for left (colored name) + right (white amount)
                    frame:AddDoubleLine(
                        string.format("%s%s:", charName, marker),
                        amountText,
                        classColor[1], classColor[2], classColor[3],  -- Left (class color)
                        1, 1, 1  -- Right (white)
                    )
                end
                
                -- Spacer before Total line
                frame:AddSpacer(8)
                
                -- Total line (COMPLETELY GREEN - both left and right)
                local FormatNumber = ns.UI_FormatNumber or function(n) return tostring(n) end
                local totalText
                if hasMaxQuantity and totalMaxQuantity > 0 then
                    totalText = string.format("%s / %s", 
                        FormatNumber(totalQuantity), 
                        FormatNumber(totalMaxQuantity))
                else
                    totalText = FormatNumber(totalQuantity)
                end
                
                frame:AddDoubleLine(
                    "Total:",
                    totalText,
                    0.4, 1, 0.4,  -- Left (green)
                    0.4, 1, 0.4   -- Right (green)
                )
            end
        end
    end
    
    -- Add custom lines
    if data.additionalLines then
        frame:AddSpacer(8)
        for _, line in ipairs(data.additionalLines) do
            if line.type == "spacer" then
                frame:AddSpacer(line.height or 8)
            elseif line.text then
                local color = line.color or {0.6, 0.4, 0.8}
                frame:AddLine(line.text, color[1], color[2], color[3], line.wrap or false)
            end
        end
    end
end

--[[
    Render hybrid tooltip (Blizzard + custom mixed)
    @param frame Frame - Tooltip frame
    @param data table - Tooltip data
]]
function TooltipService:RenderHybridTooltip(frame, data)
    -- First render Blizzard data
    if data.itemID then
        self:RenderItemTooltip(frame, data)
    elseif data.currencyID then
        self:RenderCurrencyTooltip(frame, data)
    end
    
    -- Then add custom lines (already handled in item/currency methods)
end

-- ============================================================================
-- POSITIONING
-- ============================================================================

--[[
    Position tooltip relative to anchor frame
    @param frame Frame - Tooltip frame
    @param anchorFrame Frame - Anchor frame
    @param anchor string - Anchor point
]]
function TooltipService:PositionTooltip(frame, anchorFrame, anchor)
    frame:ClearAllPoints()
    
    -- Map anchor strings to actual positioning
    if anchor == "ANCHOR_RIGHT" then
        frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 4, 0)
    elseif anchor == "ANCHOR_LEFT" then
        frame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -4, 0)
    elseif anchor == "ANCHOR_TOP" then
        frame:SetPoint("BOTTOM", anchorFrame, "TOP", 0, 4)
    elseif anchor == "ANCHOR_BOTTOM" then
        frame:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
    elseif anchor == "ANCHOR_CURSOR" then
        frame:SetPoint("BOTTOMLEFT", "UIParent", "BOTTOMLEFT", GetCursorPosition())
    else
        -- Default: right
        frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 4, 0)
    end
    
    -- Keep on screen
    self:KeepOnScreen(frame)
end

--[[
    Keep tooltip on screen (adjust position if needed)
    @param frame Frame - Tooltip frame
]]
function TooltipService:KeepOnScreen(frame)
    local scale = frame:GetEffectiveScale()
    local screenWidth = GetScreenWidth() * scale
    local screenHeight = GetScreenHeight() * scale
    
    local left = frame:GetLeft()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local bottom = frame:GetBottom()
    
    if not left or not right or not top or not bottom then
        return
    end
    
    -- Adjust if off screen
    local xOffset = 0
    local yOffset = 0
    
    if right > screenWidth then
        xOffset = screenWidth - right - 10
    elseif left < 0 then
        xOffset = -left + 10
    end
    
    if top > screenHeight then
        yOffset = screenHeight - top - 10
    elseif bottom < 0 then
        yOffset = -bottom + 10
    end
    
    if xOffset ~= 0 or yOffset ~= 0 then
        local point, relativeTo, relativePoint, x, y = frame:GetPoint()
        frame:SetPoint(point, relativeTo, relativePoint, x + xOffset, y + yOffset)
    end
end

-- ============================================================================
-- SAFETY & AUTO-HIDE
-- ============================================================================

--[[
    Register events that should auto-hide tooltip
]]
function TooltipService:RegisterSafetyEvents()
    if not WarbandNexus.RegisterEvent then return end
    
    -- Hide on combat
    WarbandNexus:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        self:Hide()
    end)
    
    -- Hide on world leave
    WarbandNexus:RegisterEvent("PLAYER_LEAVING_WORLD", function()
        self:Hide()
    end)
end

-- ============================================================================
-- GAME TOOLTIP INJECTION (TAINT-SAFE)
-- ============================================================================

--[[
    Initialize GameTooltip hook for item count display
    Uses TooltipDataProcessor (TWW API) - TAINT-SAFE
    Shows item counts across all characters + total
]]
function TooltipService:InitializeGameTooltipHook()
    -- Modern TWW API (taint-safe)
    if not TooltipDataProcessor then
        self:Debug("TooltipDataProcessor not available - tooltip injection disabled")
        return
    end
    
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        -- Only inject into GameTooltip and ItemRefTooltip (chat links)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
            return
        end
        
        -- Extract itemID from tooltip data
        local itemID = data and data.id
        if not itemID then return end
        
        -- Get detailed counts (warband bank, personal banks, character inventories)
        local details = WarbandNexus:GetDetailedItemCounts(itemID)
        if not details then return end
        
        -- Calculate total
        local total = details.warbandBank + details.personalBankTotal
        for _, char in ipairs(details.characters) do
            total = total + char.bagCount
        end
        
        if total == 0 then return end
        
        -- Add separator and title
        tooltip:AddLine(" ")
        tooltip:AddLine("WN Search", 0.4, 0.8, 1, 1)  -- Branded section title
        tooltip:AddLine(" ")  -- Extra spacing after title
        
        -- Warband Bank (left-aligned label, right-aligned count with "x" prefix)
        if details.warbandBank > 0 then
            tooltip:AddDoubleLine("Warband Bank:", "x" .. details.warbandBank, 0.8, 0.8, 0.8, 0.3, 0.9, 0.3)
        end
        
        -- Personal Bank total (left-aligned label, right-aligned count with "x" prefix)
        if details.personalBankTotal > 0 then
            tooltip:AddDoubleLine("Personal Bank:", "x" .. details.personalBankTotal, 0.8, 0.8, 0.8, 0.3, 0.9, 0.3)
        end
        
        -- Per-character inventory (top 3 only for readability)
        if #details.characters > 0 then
            local shown = 0
            for _, char in ipairs(details.characters) do
                if char.bagCount > 0 then
                    if shown >= 3 then break end  -- Limit to 3 characters
                    local classColor = RAID_CLASS_COLORS[char.classFile] or {r=1, g=1, b=1}
                    tooltip:AddDoubleLine(
                        char.charName .. ":",
                        "x" .. char.bagCount,
                        classColor.r, classColor.g, classColor.b,
                        0.3, 0.9, 0.3
                    )
                    shown = shown + 1
                end
            end
            
            -- Show "and X more" if there are more than 3 characters
            if #details.characters > 3 then
                local remaining = #details.characters - 3
                tooltip:AddLine(string.format("  ... and %d more", remaining), 0.6, 0.6, 0.6)
            end
        end
        
        -- Add total line at bottom (summary) - no spacing before
        tooltip:AddDoubleLine("Total:", "x" .. total, 1, 0.82, 0, 1, 1, 1)
        
        tooltip:Show()  -- Refresh tooltip
    end)
    
    self:Debug("GameTooltip hook initialized (TooltipDataProcessor)")
end

-- ============================================================================
-- DEBUG
-- ============================================================================

function TooltipService:Debug(msg)
    if WarbandNexus and WarbandNexus.Debug then
        WarbandNexus:Debug("[Tooltip] " .. msg)
    end
end

-- ============================================================================
-- EXPORT
-- ============================================================================

-- Attach to WarbandNexus namespace
WarbandNexus.Tooltip = TooltipService

-- Export to ns for SharedWidgets access
ns.TooltipService = TooltipService
