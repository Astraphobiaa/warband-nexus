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
        return data.itemID ~= nil or data.itemLink ~= nil
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
    
    -- Finalize layout (ensure size is correct even if no body lines were added)
    frame:LayoutLines()
    
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
    -- 1) Icon (top-left, fallback to question mark if not provided)
    if data.icon then
        frame:SetIcon(data.icon, data.iconIsAtlas)
    elseif data.title then
        -- Show fallback question mark only if there's a title (real tooltip)
        frame:SetIcon(nil)
    end
    
    -- 2) Title (always at top)
    if data.title then
        local tr, tg, tb = 1, 0.82, 0
        if data.titleColor then
            tr, tg, tb = data.titleColor[1], data.titleColor[2], data.titleColor[3]
        end
        frame:SetTitle(data.title, tr, tg, tb)
    end
    
    -- 3) Description (below title, optional)
    if data.description then
        local dr, dg, db = 0.8, 0.8, 0.8
        if data.descriptionColor then
            dr, dg, db = data.descriptionColor[1], data.descriptionColor[2], data.descriptionColor[3]
        end
        frame:SetDescription(data.description, dr, dg, db)
    end
    
    -- 4) Data lines
    if data.lines then
        for _, line in ipairs(data.lines) do
            if line.type == "spacer" then
                frame:AddSpacer(line.height or 8)
            elseif line.left and line.right then
                local leftColor = line.leftColor or {1, 1, 1}
                local rightColor = line.rightColor or {1, 1, 1}
                frame:AddDoubleLine(
                    line.left, line.right,
                    leftColor[1], leftColor[2], leftColor[3],
                    rightColor[1], rightColor[2], rightColor[3]
                )
            elseif line.left then
                local leftColor = line.leftColor or {1, 1, 1}
                frame:AddLine(line.left, leftColor[1], leftColor[2], leftColor[3], line.wrap or false)
            elseif line.text then
                local color = line.color or {1, 1, 1}
                frame:AddLine(line.text, color[1], color[2], color[3], line.wrap or false)
            end
        end
    end
end

--[[
    Render item tooltip using C_TooltipInfo (full Blizzard data in our custom frame)
    @param frame Frame - Tooltip frame
    @param data table - Tooltip data {itemID, itemLink, additionalLines}
]]
function TooltipService:RenderItemTooltip(frame, data)
    local itemID = data.itemID
    local itemLink = data.itemLink
    if not itemID and not itemLink then return end
    
    -- Get basic info for icon and fallback
    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture
    if itemLink then
        itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemLink)
    elseif itemID then
        itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
    end
    
    -- 1) Icon
    frame:SetIcon(itemTexture or nil)
    
    -- 2) Get full tooltip data via C_TooltipInfo (modern TWW API, taint-safe)
    local tooltipData = nil
    if C_TooltipInfo then
        local ok, result = pcall(function()
            if itemLink then
                return C_TooltipInfo.GetHyperlink(itemLink)
            elseif itemID then
                return C_TooltipInfo.GetItemByID(itemID)
            end
        end)
        if ok and result then
            tooltipData = result
        end
    end
    
    if tooltipData and tooltipData.lines and #tooltipData.lines > 0 then
        -- Process tooltip data lines to complete TooltipDataLine structure
        if TooltipUtil and TooltipUtil.SurfaceArgs then
            pcall(TooltipUtil.SurfaceArgs, tooltipData)
        end
        
        -- First line = item name (title)
        local firstLine = tooltipData.lines[1]
        local titleText = firstLine.leftText or itemName or "Item"
        local titleR, titleG, titleB = 1, 1, 1
        
        if firstLine.leftColor then
            titleR = firstLine.leftColor.r or 1
            titleG = firstLine.leftColor.g or 1
            titleB = firstLine.leftColor.b or 1
        elseif itemQuality then
            local qColor = ITEM_QUALITY_COLORS[itemQuality]
            if qColor then
                titleR, titleG, titleB = qColor.r, qColor.g, qColor.b
            end
        end
        
        frame:SetTitle(titleText, titleR, titleG, titleB)
        
        -- All remaining lines = item data (binding, type, ilvl, stats, effects, etc.)
        for i = 2, #tooltipData.lines do
            local line = tooltipData.lines[i]
            local leftText = line.leftText
            local rightText = line.rightText
            
            -- Skip completely empty lines (add spacer)
            if (not leftText or leftText == "") and (not rightText or rightText == "") then
                frame:AddSpacer(4)
            elseif rightText and rightText ~= "" then
                -- Double line (left + right)
                local lr, lg, lb = 1, 1, 1
                local rr, rg, rb = 1, 1, 1
                if line.leftColor then
                    lr = line.leftColor.r or 1
                    lg = line.leftColor.g or 1
                    lb = line.leftColor.b or 1
                end
                if line.rightColor then
                    rr = line.rightColor.r or 1
                    rg = line.rightColor.g or 1
                    rb = line.rightColor.b or 1
                end
                frame:AddDoubleLine(leftText or "", rightText, lr, lg, lb, rr, rg, rb)
            else
                -- Single line
                local lr, lg, lb = 1, 1, 1
                if line.leftColor then
                    lr = line.leftColor.r or 1
                    lg = line.leftColor.g or 1
                    lb = line.leftColor.b or 1
                end
                frame:AddLine(leftText, lr, lg, lb, line.wrapText or false)
            end
        end
    else
        -- Fallback: basic C_Item.GetItemInfo data
        if itemName then
            local r, g, b = 1, 1, 1
            if itemQuality then
                local qColor = ITEM_QUALITY_COLORS[itemQuality]
                if qColor then r, g, b = qColor.r, qColor.g, qColor.b end
            end
            frame:SetTitle(itemName, r, g, b)
            frame:SetDescription((ns.L and ns.L["LOADING"]) or "Loading details...", 0.7, 0.7, 0.7)
        else
            frame:SetTitle(string.format((ns.L and ns.L["ITEM_NUMBER_FORMAT"]) or "Item #%s", itemID or "?"), 1, 1, 1)
            frame:SetDescription((ns.L and ns.L["LOADING"]) or "Loading...", 0.7, 0.7, 0.7)
        end
    end
    
    -- Additional custom lines (Item ID, stack count, location, instructions, etc.)
    if data.additionalLines then
        frame:AddSpacer(8)
        for _, line in ipairs(data.additionalLines) do
            if line.type == "spacer" then
                frame:AddSpacer(line.height or 8)
            elseif line.left and line.right then
                local leftColor = line.leftColor or {1, 1, 1}
                local rightColor = line.rightColor or {1, 1, 1}
                frame:AddDoubleLine(
                    line.left, line.right,
                    leftColor[1], leftColor[2], leftColor[3],
                    rightColor[1], rightColor[2], rightColor[3]
                )
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
    
    -- 1) Icon
    frame:SetIcon(info.iconFileID or nil)
    
    -- 2) Title
    frame:SetTitle(info.name, 1, 0.82, 0)
    
    -- 3) Description
    if info.description and info.description ~= "" then
        frame:SetDescription(info.description, 1, 1, 1)
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
                    -- Support both formats: flat (currencyID = quantity) and table (currencyID = {quantity=N})
                    local rawValue = charCurrencies[currencyID]
                    local quantity, maxQuantity
                    if type(rawValue) == "table" then
                        quantity = rawValue.quantity or 0
                        maxQuantity = rawValue.maxQuantity or 0
                    else
                        quantity = tonumber(rawValue) or 0
                        maxQuantity = 0
                    end
                    
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
                frame:AddLine((ns.L and ns.L["CHARACTER_CURRENCIES"]) or "Character Currencies:", 1, 0.82, 0, false)  -- Gold (same as title)
                
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
                    local marker = charEntry.isCurrent and (" " .. ((ns.L and ns.L["YOU_MARKER"]) or "(You)")) or ""
                    
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
                
                local totalLabel = (ns.L and ns.L["TOTAL"]) or "Total"
                frame:AddDoubleLine(
                    totalLabel .. ":",
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

-- Tooltip offset constants
-- Tooltip gap from anchor
local TOOLTIP_GAP = 8

--[[
    Position tooltip with smart screen-aware placement.
    Tries the requested anchor first; if it goes off-screen, flips to the opposite side.
    @param frame Frame - Tooltip frame
    @param anchorFrame Frame - Anchor frame
    @param anchor string - Preferred anchor point
]]
function TooltipService:PositionTooltip(frame, anchorFrame, anchor)
    frame:ClearAllPoints()
    
    -- Get screen dimensions
    local screenW = GetScreenWidth()
    local screenH = GetScreenHeight()
    local tooltipW = frame:GetWidth()
    local tooltipH = frame:GetHeight()
    
    -- Get anchor frame bounds
    local aLeft = anchorFrame:GetLeft() or 0
    local aRight = anchorFrame:GetRight() or 0
    local aTop = anchorFrame:GetTop() or 0
    local aBottom = anchorFrame:GetBottom() or 0
    
    if anchor == "ANCHOR_CURSOR" then
        -- Follow cursor
        local scale = frame:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x = x / scale
        y = y / scale
        local finalX = x + 16
        local finalY = y + 4
        -- Flip if off-screen
        if finalX + tooltipW > screenW then finalX = x - tooltipW - 4 end
        if finalY + tooltipH > screenH then finalY = y - tooltipH - 4 end
        if finalX < 0 then finalX = 4 end
        if finalY < 0 then finalY = 4 end
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", finalX, finalY)
        return
    end
    
    -- Smart placement: try preferred side, flip if off-screen
    if anchor == "ANCHOR_RIGHT" or anchor == nil then
        if aRight + TOOLTIP_GAP + tooltipW <= screenW then
            frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", TOOLTIP_GAP, 0)
        else
            frame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -TOOLTIP_GAP, 0)
        end
    elseif anchor == "ANCHOR_LEFT" then
        if aLeft - TOOLTIP_GAP - tooltipW >= 0 then
            frame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -TOOLTIP_GAP, 0)
        else
            frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", TOOLTIP_GAP, 0)
        end
    elseif anchor == "ANCHOR_TOP" then
        if aTop + TOOLTIP_GAP + tooltipH <= screenH then
            frame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, TOOLTIP_GAP)
        else
            frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -TOOLTIP_GAP)
        end
    elseif anchor == "ANCHOR_BOTTOM" then
        if aBottom - TOOLTIP_GAP - tooltipH >= 0 then
            frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -TOOLTIP_GAP)
        else
            frame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, TOOLTIP_GAP)
        end
    else
        frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", TOOLTIP_GAP, 0)
    end
    
    -- Final clamp: ensure tooltip stays fully on-screen
    self:ClampToScreen(frame, screenW, screenH)
end

--[[
    Clamp tooltip frame to stay within screen boundaries.
    Adjusts position if any edge extends beyond the screen.
]]
function TooltipService:ClampToScreen(frame, screenW, screenH)
    local left = frame:GetLeft()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local bottom = frame:GetBottom()
    
    if not left or not right or not top or not bottom then return end
    
    local dx, dy = 0, 0
    local margin = 4
    
    if right > screenW - margin then dx = (screenW - margin) - right end
    if left < margin then dx = margin - left end
    if top > screenH - margin then dy = (screenH - margin) - top end
    if bottom < margin then dy = margin - bottom end
    
    if dx ~= 0 or dy ~= 0 then
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        if point and relativeTo then
            frame:ClearAllPoints()
            frame:SetPoint(point, relativeTo, relativePoint, (x or 0) + dx, (y or 0) + dy)
        end
    end
end

-- ============================================================================
-- SAFETY & AUTO-HIDE
-- ============================================================================

--[[
    Register events that should auto-hide tooltip
]]
function TooltipService:RegisterSafetyEvents()
    -- PLAYER_REGEN_DISABLED: owned by Core.lua (OnCombatStart — hides main UI + tooltip)
    -- PLAYER_LEAVING_WORLD: use dedicated frame (avoids AceEvent collision)
    local safetyFrame = CreateFrame("Frame")
    safetyFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
    safetyFrame:SetScript("OnEvent", function()
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
        -- GUARD: Check if Show Item Count is enabled (with full nil-safety)
        if not (WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.showItemCount) then
            return
        end
        
        -- Only inject into GameTooltip and ItemRefTooltip (chat links)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
            return
        end
        
        -- Extract itemID from tooltip data
        local itemID = data and data.id
        if not itemID then return end
        
        -- Get detailed counts (warband bank, personal banks, character inventories)
        -- Uses pre-indexed O(1) lookup instead of iterating all items
        local details = nil
        if WarbandNexus and WarbandNexus.GetDetailedItemCountsFast then
            details = WarbandNexus:GetDetailedItemCountsFast(itemID)
        elseif WarbandNexus and WarbandNexus.GetDetailedItemCounts then
            details = WarbandNexus:GetDetailedItemCounts(itemID)
        end
        if not details then return end
        
        -- Calculate total (warband + per-char bank + per-char bags)
        local total = details.warbandBank
        for _, char in ipairs(details.characters) do
            total = total + char.bagCount + char.bankCount
        end

        if total == 0 then return end

        -- Add separator and title
        tooltip:AddLine(" ")
        tooltip:AddLine((ns.L and ns.L["WN_SEARCH"]) or "WN Search", 0.4, 0.8, 1, 1)
        tooltip:AddLine(" ")

        -- Warband Bank
        if details.warbandBank > 0 then
            tooltip:AddDoubleLine((ns.L and ns.L["WARBAND_BANK_COLON"]) or "Warband Bank:", "x" .. details.warbandBank, 0.8, 0.8, 0.8, 0.3, 0.9, 0.3)
        end

        -- Per-character: Bank and Inventory on separate lines (limit 5 characters)
        if #details.characters > 0 then
            local shown = 0
            for _, char in ipairs(details.characters) do
                if shown >= 5 then break end
                local classColor = RAID_CLASS_COLORS[char.classFile] or {r=1, g=1, b=1}

                local bankLabel = (ns.L and ns.L["CHARACTER_BANK"]) or "Bank"
                local invLabel = (ns.L and ns.L["CHARACTER_INVENTORY"]) or "Inventory"

                if char.bankCount > 0 then
                    tooltip:AddDoubleLine(
                        char.charName .. " - " .. bankLabel .. ":",
                        "x" .. char.bankCount,
                        classColor.r, classColor.g, classColor.b,
                        0.3, 0.9, 0.3
                    )
                end

                if char.bagCount > 0 then
                    tooltip:AddDoubleLine(
                        char.charName .. " - " .. invLabel .. ":",
                        "x" .. char.bagCount,
                        classColor.r, classColor.g, classColor.b,
                        0.3, 0.9, 0.3
                    )
                end

                shown = shown + 1
            end

            if #details.characters > 5 then
                local remaining = #details.characters - 5
                tooltip:AddLine(string.format("  " .. ((ns.L and ns.L["AND_MORE_FORMAT"]) or "... and %d more"), remaining), 0.6, 0.6, 0.6)
            end
        end

        -- Total summary
        local totalLabel = (ns.L and ns.L["TOTAL"]) or "Total"
        tooltip:AddDoubleLine(totalLabel .. ":", "x" .. total, 1, 0.82, 0, 1, 1, 1)
        
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
