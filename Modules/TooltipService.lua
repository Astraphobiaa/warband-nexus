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

-- Midnight 12.0: Secret Values API (nil on pre-12.0 clients, backward-compatible)
local issecretvalue = issecretvalue
-- Upvalue for GUID parsing in object tooltip hook
local strsplit = strsplit
local tonumber = tonumber

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
    -- 1) Icon (top-left; icon=false explicitly hides icon, nil falls back to question mark)
    if data.icon == false then
        -- Explicitly no icon requested
    elseif data.icon then
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
    -- Show how much this currency exists on ALL tracked characters (including 0)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.global then
        local currencyDB = WarbandNexus.db.global.currencyData
        if currencyDB and currencyDB.currencies then
            local charQuantities = {}
            local totalQuantity = 0
            local totalMaxQuantity = 0
            local hasMaxQuantity = false
            local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
            
            -- Build tracked character list first
            local trackedChars = {}
            if WarbandNexus.db.global.characters then
                for charKey, charData in pairs(WarbandNexus.db.global.characters) do
                    if charData.isTracked ~= false then
                        trackedChars[charKey] = charData
                    end
                end
            end
            
            -- Iterate ALL tracked characters, show 0 if they don't have the currency
            local isAccountWide = info.isAccountWide or false
            local maxQuantitySeen = 0
            for charKey, charData in pairs(trackedChars) do
                local quantity = 0
                local maxQuantity = 0
                
                local charCurrencies = currencyDB.currencies[charKey]
                if charCurrencies and charCurrencies[currencyID] then
                    local rawValue = charCurrencies[currencyID]
                    if type(rawValue) == "table" then
                        quantity = rawValue.quantity or 0
                        maxQuantity = rawValue.maxQuantity or 0
                    else
                        quantity = tonumber(rawValue) or 0
                        maxQuantity = 0
                    end
                end
                
                -- Prefer classFile (English token e.g. "DEATHKNIGHT") over class (localized e.g. "Death Knight")
                local classFile = charData.classFile or charData.class or nil
                
                table.insert(charQuantities, {
                    charKey = charKey,
                    quantity = quantity,
                    maxQuantity = maxQuantity,
                    isCurrent = (charKey == currentCharKey),
                    classFile = classFile
                })
                if not isAccountWide then
                    totalQuantity = totalQuantity + quantity
                    if maxQuantity and maxQuantity > 0 then
                        hasMaxQuantity = true
                        totalMaxQuantity = totalMaxQuantity + maxQuantity
                    end
                else
                    -- Warband (account-wide): one shared pool — use max, not sum
                    if quantity > totalQuantity then totalQuantity = quantity end
                    if maxQuantity and maxQuantity > maxQuantitySeen then
                        maxQuantitySeen = maxQuantity
                        hasMaxQuantity = true
                    end
                end
            end
            if isAccountWide and maxQuantitySeen > 0 then
                totalMaxQuantity = maxQuantitySeen
            end
            
            -- Sort: Current character first, then by quantity descending, then alphabetically
            table.sort(charQuantities, function(a, b)
                if a.isCurrent ~= b.isCurrent then
                    return a.isCurrent
                end
                if a.quantity ~= b.quantity then
                    return a.quantity > b.quantity
                end
                return a.charKey < b.charKey
            end)
            
            -- Show currency amount (account-wide: note + single balance; character: full breakdown)
            if #charQuantities > 0 then
                local FormatNumber = ns.UI_FormatNumber or function(n) return tostring(n) end
                local totalText
                if hasMaxQuantity and totalMaxQuantity > 0 then
                    totalText = string.format("%s / %s",
                        FormatNumber(totalQuantity),
                        FormatNumber(totalMaxQuantity))
                else
                    totalText = FormatNumber(totalQuantity)
                end

                if isAccountWide then
                    -- Warband: only the note and balance, no character list
                    frame:AddLine((ns.L and ns.L["CURRENCY_ACCOUNT_WIDE_NOTE"]) or "Account-wide (Warband) — same balance on all characters.", 0.6, 0.8, 1, false)
                    local totalLabel = (ns.L and ns.L["TOTAL"]) or "Total"
                    frame:AddDoubleLine(
                        totalLabel .. ":",
                        totalText,
                        0.4, 1, 0.4,
                        0.4, 1, 0.4
                    )
                else
                    -- Character-specific: full breakdown (REPUTATION STYLE)
                    -- Respect "Hide Empty" setting: skip 0-quantity characters when currencyShowZero is false
                    local hideZero = WarbandNexus.db and WarbandNexus.db.profile and not WarbandNexus.db.profile.currencyShowZero
                    frame:AddLine((ns.L and ns.L["CHARACTER_CURRENCIES"]) or "Character Currencies:", 1, 0.82, 0, false)
                    for _, charEntry in ipairs(charQuantities) do
                        -- Skip 0-quantity characters in Hide Empty mode (always show current character)
                        if hideZero and charEntry.quantity == 0 and not charEntry.isCurrent then
                            -- skip
                        else
                        local charName = charEntry.charKey:match("^([^%-]+)") or charEntry.charKey
                        local classColor = {0.7, 0.7, 0.7}
                        local classKey = charEntry.classFile or charEntry.class
                        if classKey then
                            classKey = string.upper(tostring(classKey))
                            local classColorObj = C_ClassColor and C_ClassColor.GetClassColor(classKey)
                            if classColorObj then
                                classColor = {classColorObj.r, classColorObj.g, classColorObj.b}
                            elseif RAID_CLASS_COLORS and RAID_CLASS_COLORS[classKey] then
                                local c = RAID_CLASS_COLORS[classKey]
                                classColor = {c.r, c.g, c.b}
                            end
                        end
                        local marker = charEntry.isCurrent and (" " .. ((ns.L and ns.L["YOU_MARKER"]) or "(You)")) or ""
                        local amountText
                        if hasMaxQuantity and charEntry.maxQuantity and charEntry.maxQuantity > 0 then
                            amountText = string.format("%s / %s",
                                FormatNumber(charEntry.quantity),
                                FormatNumber(charEntry.maxQuantity))
                        else
                            amountText = FormatNumber(charEntry.quantity)
                        end
                        local leftR, leftG, leftB = classColor[1], classColor[2], classColor[3]
                        local rightR, rightG, rightB = 1, 1, 1
                        if charEntry.quantity == 0 then
                            leftR, leftG, leftB = 0.4, 0.4, 0.4
                            rightR, rightG, rightB = 0.4, 0.4, 0.4
                        end
                        frame:AddDoubleLine(
                            string.format("%s%s:", charName, marker),
                            amountText,
                            leftR, leftG, leftB,
                            rightR, rightG, rightB
                        )
                        end -- hideZero filter
                    end
                    frame:AddSpacer(8)
                    local totalLabel = (ns.L and ns.L["TOTAL"]) or "Total"
                    frame:AddDoubleLine(
                        totalLabel .. ":",
                        totalText,
                        0.4, 1, 0.4,
                        0.4, 1, 0.4
                    )
                end
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
-- SHARED COLLECTIBLE DROP LINES (used by Unit, Item, and Object tooltip hooks)
-- ============================================================================

---Inject collectible drop lines into a GameTooltip.
---Shows header, item hyperlinks, collected/repeatable status, and try counts.
---Shared across NPC (Unit), Container (Item), and Object tooltip hooks.
---@param tooltip Frame GameTooltip or compatible tooltip frame
---@param drops table Array of drop entries { type, itemID, name [, guaranteed] [, repeatable] }
local function InjectCollectibleDropLines(tooltip, drops)
    if not drops or #drops == 0 then return end

    local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo

    -- Header
    tooltip:AddLine(" ")
    tooltip:AddLine("Collectible Drops", 0.58, 0.44, 0.86) -- WN purple

    for i = 1, #drops do
        local drop = drops[i]

        -- Get item hyperlink (quality-colored, bracketed)
        local _, itemLink
        if GetItemInfo then
            _, itemLink = GetItemInfo(drop.itemID)
        end
        if not itemLink then
            -- Item not cached yet — queue for next hover, use DB name as fallback
            if C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, drop.itemID)
            end
            itemLink = "|cffff8000[" .. (drop.name or "Unknown") .. "]|r"
        end

        -- Collection status check
        local collected = false
        local collectibleID = nil

        if drop.type == "mount" then
            if C_MountJournal and C_MountJournal.GetMountFromItem then
                collectibleID = C_MountJournal.GetMountFromItem(drop.itemID)
                if issecretvalue and collectibleID and issecretvalue(collectibleID) then
                    collectibleID = nil
                end
            end
            if collectibleID then
                local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(collectibleID)
                if not (issecretvalue and isCollected and issecretvalue(isCollected)) then
                    collected = isCollected == true
                end
            end
        elseif drop.type == "pet" then
            if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                collectibleID = C_PetJournal.GetPetInfoByItemID(drop.itemID)
                if issecretvalue and collectibleID and issecretvalue(collectibleID) then
                    collectibleID = nil
                end
            end
            if collectibleID then
                local numCollected = C_PetJournal.GetNumCollectedInfo(collectibleID)
                if not (issecretvalue and numCollected and issecretvalue(numCollected)) then
                    collected = numCollected and numCollected > 0
                end
            end
        elseif drop.type == "toy" then
            if PlayerHasToy then
                local hasToy = PlayerHasToy(drop.itemID)
                if not (issecretvalue and hasToy and issecretvalue(hasToy)) then
                    collected = hasToy == true
                end
            end
        end

        -- Check repeatable and guaranteed flags
        local isRepeatable = drop.repeatable
        local isGuaranteed = drop.guaranteed
        if not isGuaranteed and WarbandNexus and WarbandNexus.IsGuaranteedCollectible then
            isGuaranteed = WarbandNexus:IsGuaranteedCollectible(drop.type, collectibleID or drop.itemID)
        end
        if not isRepeatable and WarbandNexus and WarbandNexus.IsRepeatableCollectible then
            isRepeatable = WarbandNexus:IsRepeatableCollectible(drop.type, collectibleID or drop.itemID)
        end

        -- Try count (do not show for 100% guaranteed drops)
        local tryCount = 0
        if not isGuaranteed and WarbandNexus and WarbandNexus.GetTryCount then
            if collectibleID then
                tryCount = WarbandNexus:GetTryCount(drop.type, collectibleID)
            end
            if tryCount == 0 then
                tryCount = WarbandNexus:GetTryCount(drop.type, drop.itemID)
            end
        end

        -- Build right-side status text
        local rightText
        if isRepeatable then
            -- Repeatable: always show attempts, never "Collected"
            if tryCount > 0 then
                rightText = "|cffffff00" .. tryCount .. " attempts|r |cffaaaaaa(Repeatable)|r"
            else
                rightText = "|cffaaaaaa(Repeatable)|r"
            end
        elseif collected then
            rightText = "|cff00ff00Collected|r"
        elseif isGuaranteed then
            rightText = "|cff00ff00100% Drop|r"
        elseif tryCount > 0 then
            rightText = "|cffffff00" .. tryCount .. " attempts|r"
        else
            local typeLabels = { mount = "Mount", pet = "Pet", toy = "Toy" }
            rightText = "|cff888888" .. (typeLabels[drop.type] or "") .. "|r"
        end

        tooltip:AddDoubleLine(
            "  " .. itemLink,
            rightText,
            1, 1, 1,  -- left color (overridden by hyperlink color codes)
            1, 1, 1   -- right color (overridden by inline color codes)
        )
    end

    tooltip:Show()
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

    -- Coordination flag: prevents recipe hook from duplicating when tier injection already handled
    local lastWNReagentItemID = nil
    
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

        -- ============================================================
        -- TIER-AWARE REAGENT DISPLAY (bags, bank, AH, anywhere)
        -- If this item belongs to a quality tier group, show R1/R2/R3
        -- ============================================================
        local tierGroup = WarbandNexus.GetTierGroupForItem and WarbandNexus:GetTierGroupForItem(itemID)
        if tierGroup and tierGroup.tiers and #tierGroup.tiers > 1 then
            -- Shared helpers from ProfessionCacheService
            local TierTag = ns.TierTag or function(i) return "R" .. i end
            local AmountColor = ns.AmountColor or function(a) return a > 0 and "44ff44" or "555555" end
            local ClassColoredName = ns.ClassColoredName or function(n) return n end

            -- Collect per-tier totals and per-character data
            local tierTotals = {}       -- { [tierIdx] = total }
            local charMap = {}          -- { charName = { classFile, counts = {[tierIdx]=N} } }
            local charOrder = {}
            local wbCounts = {}         -- { [tierIdx] = warbandBankCount }
            local hasWarband = false
            local grandTotal = 0

            for tierIdx, tierItemID in ipairs(tierGroup.tiers) do
                local counts = WarbandNexus:GetDetailedItemCountsFast(tierItemID)
                local tierTotal = 0
                local wbCount = 0

                if counts then
                    wbCount = counts.warbandBank or 0
                    tierTotal = tierTotal + wbCount
                    if wbCount > 0 then hasWarband = true end

                    for _, ch in ipairs(counts.characters or {}) do
                        tierTotal = tierTotal + (ch.total or 0)
                        if ch.total and ch.total > 0 then
                            local key = ch.charName or "?"
                            if not charMap[key] then
                                charMap[key] = { classFile = ch.classFile, counts = {} }
                                table.insert(charOrder, key)
                            end
                            charMap[key].counts[tierIdx] = (charMap[key].counts[tierIdx] or 0) + ch.total
                        end
                    end
                end

                tierTotals[tierIdx] = tierTotal
                wbCounts[tierIdx] = wbCount
                grandTotal = grandTotal + tierTotal
            end

            if grandTotal == 0 then
                -- No stock at all, skip
            else
                tooltip:AddLine(" ")
                tooltip:AddLine("Warband Nexus - Reagents", 0.4, 0.8, 1)

                -- Reagent header: Name (left)  R1 total  R2 total  R3 total (right)
                local itemName = GetItemInfo(tierGroup.baseItemID) or ("Item " .. tierGroup.baseItemID)
                local tierParts = {}
                for tierIdx = 1, #tierGroup.tiers do
                    local have = tierTotals[tierIdx] or 0
                    local col = AmountColor(have)
                    table.insert(tierParts, TierTag(tierIdx) .. "|cff" .. col .. have .. "|r")
                end
                tooltip:AddDoubleLine(
                    "|cffdadada" .. itemName .. "|r",
                    table.concat(tierParts, " "),
                    1, 1, 1, 1, 1, 1
                )

                -- Per-character rows
                for _, charName in ipairs(charOrder) do
                    local info = charMap[charName]
                    local charParts = {}
                    for tierIdx = 1, #tierGroup.tiers do
                        local count = info.counts[tierIdx] or 0
                        local col = count > 0 and "ffffff" or "555555"
                        table.insert(charParts, TierTag(tierIdx) .. "|cff" .. col .. count .. "|r")
                    end
                    tooltip:AddDoubleLine(
                        ClassColoredName(charName, info.classFile),
                        table.concat(charParts, " "),
                        1, 1, 1, 1, 1, 1
                    )
                end

                -- Warband bank row
                if hasWarband then
                    local wbParts = {}
                    for tierIdx = 1, #tierGroup.tiers do
                        local wc = wbCounts[tierIdx] or 0
                        local col = wc > 0 and "ffffff" or "555555"
                        table.insert(wbParts, TierTag(tierIdx) .. "|cff" .. col .. wc .. "|r")
                    end
                    tooltip:AddDoubleLine(
                        "|cffddaa44Warband Bank|r",
                        table.concat(wbParts, " "),
                        1, 1, 1, 1, 1, 1
                    )
                end

                lastWNReagentItemID = itemID
                tooltip:Show()
                return
            end
        end

        -- ============================================================
        -- STANDARD WN SEARCH (non-reagent items or no tier data)
        -- ============================================================
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
    
    -- ----------------------------------------------------------------
    -- UNIT TOOLTIP: Collectible drop info from CollectibleSourceDB
    -- Shows item hyperlinks + collection status + try count on NPCs
    -- ----------------------------------------------------------------
    if Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        -- Upvalue WoW APIs used in the hook
        local UnitGUID = UnitGUID
        local strsplit = strsplit
        local tonumber = tonumber
        local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
        local C_MountJournal = C_MountJournal
        local C_PetJournal = C_PetJournal
        local PlayerHasToy = PlayerHasToy

        -- Runtime name → drops cache (populated from successful GUID lookups)
        local nameDropCache = {}

        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
            if tooltip ~= GameTooltip then return end

            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB or not sourceDB.npcs then return end

            local drops = nil

            -- METHOD 1: GUID-based lookup (works outside instances / when not secret)
            local ok, guid = pcall(UnitGUID, "mouseover")
            if ok and guid and not (issecretvalue and issecretvalue(guid)) then
                local unitType, _, _, _, _, rawID = strsplit("-", guid)
                if unitType == "Creature" or unitType == "Vehicle" then
                    local npcID = tonumber(rawID)
                    if npcID then
                        drops = sourceDB.npcs[npcID]
                        -- Cache name → drops for future secret-value fallback
                        if drops and #drops > 0 then
                            local ttLeft = _G["GameTooltipTextLeft1"]
                            if ttLeft and ttLeft.GetText then
                                local nm = ttLeft:GetText()
                                if nm and not (issecretvalue and issecretvalue(nm)) and nm ~= "" then
                                    nameDropCache[nm] = drops
                                end
                            end
                        end
                    end
                end
                if not drops then return end
            end

            -- METHOD 2: Name-based fallback (Midnight 12.0 - GUID is secret in instances)
            if not drops then
                -- Read NPC name from multiple sources (Blizzard renders these from secure code)
                local unitName = nil

                -- Try tooltip data lines first (most reliable in Midnight)
                if data and data.lines and data.lines[1] then
                    local lt = data.lines[1].leftText
                    -- Guard: leftText can itself be a secret value in Midnight instances
                    if lt and not (issecretvalue and issecretvalue(lt)) then
                        unitName = lt
                    end
                end

                -- Fallback: read from the tooltip's font string directly
                if not unitName then
                    local textLeft = _G["GameTooltipTextLeft1"]
                    if textLeft and textLeft.GetText then
                        local txt = textLeft:GetText()
                        if txt and not (issecretvalue and issecretvalue(txt)) then
                            unitName = txt
                        end
                    end
                end

                -- If everything is secret, we simply can't identify this NPC — bail out
                if not unitName or unitName == "" then return end

                -- Check runtime cache first (populated from previous GUID-based lookups)
                drops = nameDropCache[unitName]

                -- Check static npcNameIndex (covers instance bosses)
                if not drops and sourceDB.npcNameIndex then
                    local npcIDs = sourceDB.npcNameIndex[unitName]
                    if npcIDs then
                        -- Merge drops from all matching NPC IDs
                        local merged = {}
                        local seen = {} -- Dedup by itemID
                        for _, npcID in ipairs(npcIDs) do
                            local npcDrops = sourceDB.npcs[npcID]
                            if npcDrops then
                                for j = 1, #npcDrops do
                                    local d = npcDrops[j]
                                    if not seen[d.itemID] then
                                        seen[d.itemID] = true
                                        merged[#merged + 1] = d
                                    end
                                end
                            end
                        end
                        if #merged > 0 then
                            drops = merged
                        end
                    end
                end

                if not drops or #drops == 0 then return end
            end

            -- Use shared rendering function
            InjectCollectibleDropLines(tooltip, drops)
        end)

        self:Debug("Unit tooltip hook initialized (collectible drops)")
    end

    -- ----------------------------------------------------------------
    -- ITEM TOOLTIP: Container collectible drops (paragon caches, bags, etc.)
    -- Checks CollectibleSourceDB.containers for the hovered item and injects
    -- collectible drop lines if found.
    -- ----------------------------------------------------------------
    if Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end

            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB or not sourceDB.containers then return end

            local itemID = data and data.id
            if not itemID then return end

            local containerData = sourceDB.containers[itemID]
            if not containerData then return end

            local drops = containerData.drops or containerData
            if not drops or type(drops) ~= "table" or #drops == 0 then return end

            InjectCollectibleDropLines(tooltip, drops)
        end)

        self:Debug("Container item tooltip hook initialized (collectible drops)")
    end

    -- ----------------------------------------------------------------
    -- OBJECT TOOLTIP: Chest/Cache collectible drops from CollectibleSourceDB.objects
    -- GameTooltip:HookScript("OnShow") fallback for world objects/chests.
    -- TooltipDataProcessor does not have a native GameObject type,
    -- so we use the OnTooltipSetDefaultAnchor / OnShow hook approach.
    -- ----------------------------------------------------------------
    do
        local sourceDB = ns.CollectibleSourceDB
        if sourceDB and sourceDB.objects and next(sourceDB.objects) then
            -- Hook GameTooltip OnShow to check for GameObject targets
            GameTooltip:HookScript("OnShow", function(tooltip)
                local sourceDB = ns.CollectibleSourceDB
                if not sourceDB or not sourceDB.objects then return end

                -- Try to get the moused-over unit's GUID as a GameObject
                local ok, guid = pcall(UnitGUID, "mouseover")
                if not ok or not guid then
                    -- No mouseover unit — try GetMouseFocus fallback for world objects
                    -- World objects don't have a UnitGUID, but the tooltip may have
                    -- been set via SetGameObject or similar methods.
                    -- Attempt to read from tooltip data (TWW+)
                    if tooltip.GetTooltipData then
                        local tData = tooltip:GetTooltipData()
                        if tData and tData.type and tData.guid then
                            guid = tData.guid
                        end
                    end
                end

                if not guid then return end
                if issecretvalue and issecretvalue(guid) then return end

                -- Parse GameObject GUID: "GameObject-0-XXXX-XXXX-XXXX-XXXX-objectID"
                local unitType, _, _, _, _, rawID = strsplit("-", guid)
                if unitType ~= "GameObject" then return end

                local objectID = tonumber(rawID)
                if not objectID then return end

                local drops = sourceDB.objects[objectID]
                if not drops or #drops == 0 then return end

                InjectCollectibleDropLines(tooltip, drops)
            end)

            self:Debug("Object tooltip hook initialized (chest/cache collectible drops)")
        end
    end

    -- ----------------------------------------------------------------
    -- RECIPE TOOLTIP: Reagent availability from storage (profession UI)
    -- Hook SetRecipeResultItem to capture recipeSpellID, then inject
    -- per-tier reagent availability into the tooltip.
    -- Fallback: reverse-map outputItemID → recipeID if hook unavailable.
    -- ----------------------------------------------------------------
    local lastRecipeSpellID = nil

    -- Try to hook SetRecipeResultItem (used by profession UI recipe list)
    if GameTooltip.SetRecipeResultItem then
        hooksecurefunc(GameTooltip, "SetRecipeResultItem", function(self, recipeSpellID)
            lastRecipeSpellID = recipeSpellID
        end)
        self:Debug("Hooked GameTooltip:SetRecipeResultItem for recipe tooltips")
    end

    -- Build reverse map: outputItemID → recipeID (lazy, cached)
    local outputToRecipeMap = nil
    local function GetOutputToRecipeMap()
        if outputToRecipeMap then return outputToRecipeMap end
        outputToRecipeMap = {}
        local recipeCache = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.professionRecipes
        if recipeCache then
            for recipeID, meta in pairs(recipeCache) do
                if meta.outputItemID then
                    outputToRecipeMap[meta.outputItemID] = recipeID
                end
            end
        end
        -- Invalidate after 10s so new scans are picked up
        C_Timer.After(10, function() outputToRecipeMap = nil end)
        return outputToRecipeMap
    end

    -- Inject reagent availability after recipe item tooltip renders
    -- Uses the shared InjectReagentTooltipLines from ProfessionCacheService
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip then return end
        if not (WarbandNexus and WarbandNexus.db and WarbandNexus.InjectReagentTooltipLines) then return end

        -- Skip if tier injection already handled this item (prevents duplicate)
        local itemID = data and data.id
        if itemID and itemID == lastWNReagentItemID then
            lastWNReagentItemID = nil
            return
        end
        lastWNReagentItemID = nil

        -- Determine recipeID: prefer captured spellID, fallback to reverse map
        local recipeID = lastRecipeSpellID
        lastRecipeSpellID = nil  -- consume so it doesn't leak to non-recipe tooltips

        if not recipeID then
            if itemID then
                local revMap = GetOutputToRecipeMap()
                recipeID = revMap[itemID]
            end
        end

        if not recipeID then return end

        -- Only show when profession UI is open
        if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady or not C_TradeSkillUI.IsTradeSkillReady() then
            return
        end

        -- Use shared injector (DRY)
        WarbandNexus:InjectReagentTooltipLines(tooltip, nil, recipeID)

        -- Craftable count
        local craftable = WarbandNexus:GetCraftableCount(nil, recipeID)
        local cr, cg, cb = craftable > 0 and 0.3 or 1, craftable > 0 and 1 or 0.4, craftable > 0 and 0.3 or 0.4
        tooltip:AddLine("Craftable: |cff" .. string.format("%02x%02x%02x", cr*255, cg*255, cb*255) .. craftable .. "x|r", 1, 0.82, 0)

        tooltip:Show()
    end)

    self:Debug("Recipe tooltip hook initialized (reagent availability)")

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
