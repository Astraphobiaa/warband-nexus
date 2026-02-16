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
---@param npcID number|nil Optional NPC ID for lockout quest checking
local function InjectCollectibleDropLines(tooltip, drops, npcID)
    if not drops or #drops == 0 then return end

    local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    local sourceDB = ns.CollectibleSourceDB

    -- Check daily/weekly lockout status for this NPC
    local isLockedOut = false
    if npcID and sourceDB and sourceDB.lockoutQuests then
        local questData = sourceDB.lockoutQuests[npcID]
        if questData then
            local questIDs = type(questData) == "table" and questData or { questData }
            if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
                for qi = 1, #questIDs do
                    if C_QuestLog.IsQuestFlaggedCompleted(questIDs[qi]) then
                        isLockedOut = true
                        break
                    end
                end
            end
        end
    end

    -- Spacer before drop lines
    tooltip:AddLine(" ")

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

        if drop.type == "item" then
            -- Generic items (e.g. Miscellaneous Mechanica): collectibleID == itemID, never "collected"
            collectibleID = drop.itemID
            collected = false
        elseif drop.type == "mount" then
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
                -- speciesID is the 13th return value, NOT the 1st (which is pet name)
                local _, _, _, _, _, _, _, _, _, _, _, _, specID = C_PetJournal.GetPetInfoByItemID(drop.itemID)
                collectibleID = specID
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
        -- Repeatable items: always show try counter (even 0) on the item line,
        -- then a separate "Collected" line underneath when owned.
        -- Non-repeatable: show Collected OR try count, not both.
        -- Locked out: everything gray.
        local rightText
        local showCollectedLine = false  -- extra line below for repeatable collected status
        if isRepeatable then
            local attemptsColor = isLockedOut and "666666" or "ffff00"
            rightText = "|cff" .. attemptsColor .. tryCount .. " attempts|r"
            if collected then
                showCollectedLine = true
            end
        elseif isLockedOut and not collected then
            if tryCount > 0 then
                rightText = "|cff666666" .. tryCount .. " attempts|r"
            else
                rightText = ""
            end
        elseif collected then
            rightText = "|cff00ff00Collected|r"
        elseif isGuaranteed then
            rightText = "|cff00ff00100% Drop|r"
        elseif tryCount > 0 then
            rightText = "|cffffff00" .. tryCount .. " attempts|r"
        else
            rightText = ""
        end

        -- When locked out and not collected, dim the item link to gray
        local displayLink = itemLink
        if isLockedOut and not collected then
            local plainName = drop.name or "Unknown"
            if itemLink then
                local linkName = itemLink:match("%[(.-)%]")
                if linkName then plainName = linkName end
            end
            displayLink = "|cff666666[" .. plainName .. "]|r"
        end

        tooltip:AddDoubleLine(
            displayLink,
            rightText,
            1, 1, 1,  -- left color (overridden by hyperlink color codes)
            1, 1, 1   -- right color (overridden by inline color codes)
        )

        -- Repeatable + collected: add a "Collected" status line below the item
        if showCollectedLine then
            tooltip:AddDoubleLine(
                "   |cff00ff00Collected|r",
                "",
                1, 1, 1,
                1, 1, 1
            )
        end
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

    -- ================================================================
    -- ITEM TOOLTIP HANDLER — WN Search counts per character
    -- ================================================================
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not (WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
                and WarbandNexus.db.profile.showItemCount) then
            return
        end
        if not tooltip or not tooltip.AddLine or not tooltip.AddDoubleLine then return end

        local itemID = data and data.id
        if not itemID then return end

        local ok, err = pcall(function()
            local details = WarbandNexus:GetDetailedItemCountsFast(itemID)
            if not details then return end

            local total = details.warbandBank or 0
            for i = 1, #details.characters do
                total = total + details.characters[i].bagCount + details.characters[i].bankCount
            end
            if total == 0 then return end

            tooltip:AddLine(" ")
            tooltip:AddLine((ns.L and ns.L["WN_SEARCH"]) or "WN Search", 0.4, 0.8, 1, 1)

            -- Atlas markup for storage type icons (uniform 16x16)
            local bagIcon     = CreateAtlasMarkup and CreateAtlasMarkup("Banker", 16, 16) or ""
            local bankIcon    = CreateAtlasMarkup and CreateAtlasMarkup("VignetteLoot", 16, 16) or ""
            local warbandIcon = CreateAtlasMarkup and CreateAtlasMarkup("warbands-icon", 16, 16) or ""

            if details.warbandBank > 0 then
                tooltip:AddDoubleLine(
                    warbandIcon .. " Warband Bank",
                    "x" .. details.warbandBank,
                    0.8, 0.8, 0.8, 0.3, 0.9, 0.3
                )
            end

            if #details.characters > 0 then
                local isShift = IsShiftKeyDown()
                local maxShow = isShift and 999 or 5
                local shown = 0

                for i = 1, #details.characters do
                    if shown >= maxShow then break end
                    local char = details.characters[i]
                    local cc   = RAID_CLASS_COLORS[char.classFile] or { r = 1, g = 1, b = 1 }

                    if char.bankCount > 0 then
                        tooltip:AddDoubleLine(
                            bankIcon .. " " .. char.charName,
                            "x" .. char.bankCount,
                            cc.r, cc.g, cc.b, 0.3, 0.9, 0.3
                        )
                    end
                    if char.bagCount > 0 then
                        tooltip:AddDoubleLine(
                            bagIcon .. " " .. char.charName,
                            "x" .. char.bagCount,
                            cc.r, cc.g, cc.b, 0.3, 0.9, 0.3
                        )
                    end
                    shown = shown + 1
                end

                if not isShift and #details.characters > 5 then
                    tooltip:AddLine("  Hold [Shift] for full list", 0.5, 0.5, 0.5)
                end
            end

            local totalLabel = (ns.L and ns.L["TOTAL"]) or "Total"
            tooltip:AddDoubleLine(totalLabel .. ":", "x" .. total, 1, 0.82, 0, 1, 1, 1)
            tooltip:Show()
        end)

        if not ok and WarbandNexus.Debug then
            WarbandNexus:Debug("[Tooltip] Item PostCall error for itemID " .. tostring(itemID) .. ": " .. tostring(err))
        end
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

        -- Runtime name → drops cache (populated from successful GUID lookups)
        local nameDropCache = {}

        -- Runtime name → npcID cache (for lockout quest checking in name-fallback mode)
        local nameNpcIDCache = {}

        -- Localized npcNameIndex: built in the BACKGROUND using a coroutine to prevent
        -- game freezes. The old synchronous approach iterated ALL EJ tiers → instances →
        -- encounters → creatures (thousands of API calls) and froze the game for 10-15 seconds.
        --
        -- ARCHITECTURE:
        -- 1. Initialize immediately with English fallback from CollectibleSourceDB.npcNameIndex
        -- 2. Check SavedVariables cache — if locale + version match, load and SKIP EJ scan
        -- 3. If no cache: start a background coroutine that scans EJ for localized names
        -- 4. After EJ scan completes, save results to cache for future logins
        -- 5. Tooltip handler always has a working index (English until localized names arrive)
        local localizedNpcNameIndex = {}  -- Starts populated with English fallback
        local npcIndexBuildComplete = false  -- true when background coroutine finishes

        -- Immediately populate with English fallback so tooltips work before EJ scan
        local function InitializeEnglishFallback()
            local sourceDB = ns.CollectibleSourceDB
            if sourceDB and sourceDB.npcNameIndex then
                for name, npcIDs in pairs(sourceDB.npcNameIndex) do
                    localizedNpcNameIndex[name] = npcIDs
                end
            end
        end
        InitializeEnglishFallback()

        -- Compute a simple version fingerprint from CollectibleSourceDB.
        -- Changes when encounters or npcNameIndex is modified (addon update).
        local function GetCacheVersion()
            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB then return 0 end
            local count = 0
            if sourceDB.encounters then
                for _ in pairs(sourceDB.encounters) do count = count + 1 end
            end
            if sourceDB.npcNameIndex then
                for _ in pairs(sourceDB.npcNameIndex) do count = count + 1 end
            end
            if sourceDB.npcs then
                for _ in pairs(sourceDB.npcs) do count = count + 1 end
            end
            return count
        end

        -- Try to load cached localized names from SavedVariables.
        -- Returns true if cache was valid and loaded.
        local function TryLoadFromCache()
            local addon = WarbandNexus or _G[addonName]
            if not addon or not addon.db or not addon.db.global then return false end

            local cache = addon.db.global.npcNameCache
            if not cache then return false end

            local currentLocale = GetLocale()
            local currentVersion = GetCacheVersion()

            if cache.locale ~= currentLocale or cache.version ~= currentVersion then
                -- Cache is stale (locale changed or DB updated)
                addon.db.global.npcNameCache = nil
                return false
            end

            -- Load cached names into the index
            local loaded = 0
            for name, npcIDs in pairs(cache.names) do
                localizedNpcNameIndex[name] = npcIDs
                loaded = loaded + 1
            end

            npcIndexBuildComplete = true
            if addon.Debug then
                addon:Debug("[Tooltip] NPC name index loaded from cache: %d names (locale: %s)", loaded, currentLocale)
            end
            return true
        end

        -- Save current localized names to SavedVariables cache.
        local function SaveToCache(ejEntries)
            local addon = WarbandNexus or _G[addonName]
            if not addon or not addon.db or not addon.db.global then return end

            -- Only save EJ-derived entries (not the English fallback from npcNameIndex)
            local names = {}
            local sourceDB = ns.CollectibleSourceDB
            local englishNames = (sourceDB and sourceDB.npcNameIndex) or {}

            for name, npcIDs in pairs(localizedNpcNameIndex) do
                -- Save ALL names (English + localized) so cache is self-contained
                -- Strip _seen metadata
                local clean = {}
                for i = 1, #npcIDs do
                    clean[i] = npcIDs[i]
                end
                names[name] = clean
            end

            addon.db.global.npcNameCache = {
                locale = GetLocale(),
                version = GetCacheVersion(),
                names = names,
            }

            if addon.Debug then
                local count = 0
                for _ in pairs(names) do count = count + 1 end
                addon:Debug("[Tooltip] NPC name index saved to cache: %d names", count)
            end
        end

        -- EJ SCAN REMOVED: The Encounter Journal scan iterated ~200 instances causing
        -- unavoidable FPS drops (each EJ_SelectInstance triggers WoW internal data loading).
        -- The 94 localized names it produced are NOT worth 6+ seconds of frame spikes.
        --
        -- Coverage without EJ scan:
        -- 1. English fallback names from CollectibleSourceDB.npcNameIndex (always available)
        -- 2. GUID-based method extracts NPC ID directly (works in most cases)
        -- 3. Runtime nameDropCache: populated from successful GUID lookups
        -- 4. ENCOUNTER_LOOT_RECEIVED handler: adds localized boss names at runtime
        -- 5. SavedVariables cache: persists any previously scanned names across sessions
        --
        -- The only gap: non-English client + secret GUID + first time seeing a boss.
        -- This resolves itself after one successful GUID lookup or boss kill.

        -- Load any previously cached names from SavedVariables (from older sessions)
        C_Timer.After(1.5, function()
            TryLoadFromCache()
            npcIndexBuildComplete = true
        end)

        -- Accessor: always returns the index (English fallback until EJ scan completes)
        local function GetLocalizedNpcNameIndex()
            return localizedNpcNameIndex
        end

        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
            if tooltip ~= GameTooltip then return end

            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB or not sourceDB.npcs then return end

            local drops = nil
            local resolvedNpcID = nil  -- Track NPC ID for lockout quest checking

            -- METHOD 1: GUID-based lookup (works outside instances / when not secret)
            local ok, guid = pcall(UnitGUID, "mouseover")
            if ok and guid and not (issecretvalue and issecretvalue(guid)) then
                local unitType, _, _, _, _, rawID = strsplit("-", guid)
                if unitType == "Creature" or unitType == "Vehicle" then
                    local npcID = tonumber(rawID)
                    if npcID then
                        drops = sourceDB.npcs[npcID]
                        if drops then resolvedNpcID = npcID end
                        -- Cache name → drops and name → npcID for future secret-value fallback
                        if drops and #drops > 0 then
                            local ttLeft = _G["GameTooltipTextLeft1"]
                            if ttLeft and ttLeft.GetText then
                                local nm = ttLeft:GetText()
                                if nm and not (issecretvalue and issecretvalue(nm)) and nm ~= "" then
                                    nameDropCache[nm] = drops
                                    nameNpcIDCache[nm] = npcID
                                    -- Also persist to localizedNpcNameIndex for cross-session cache
                                    if not localizedNpcNameIndex[nm] then
                                        localizedNpcNameIndex[nm] = { npcID }
                                    end
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
                if drops then
                    resolvedNpcID = nameNpcIDCache[unitName]
                end

                -- Check localized npcNameIndex (covers instance bosses, locale-aware)
                if not drops then
                    local npcIDs = GetLocalizedNpcNameIndex()[unitName]
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
                            -- Use first NPC ID for lockout checking
                            resolvedNpcID = npcIDs[1]
                        end
                    end
                end

                if not drops or #drops == 0 then return end
            end

            -- Use shared rendering function (pass npcID for lockout checking)
            InjectCollectibleDropLines(tooltip, drops, resolvedNpcID)
        end)

        -- Expose diagnostic accessors (MUST be inside this scope to access closures)
        self._getLocalizedNpcNameIndex = GetLocalizedNpcNameIndex
        self._isNpcIndexReady = function() return npcIndexBuildComplete end
        -- Force rebuild: resets to English fallback and reloads cache
        self._forceRebuildIndex = function()
            localizedNpcNameIndex = {}
            npcIndexBuildComplete = false
            InitializeEnglishFallback()
            TryLoadFromCache()
            npcIndexBuildComplete = true
            return localizedNpcNameIndex
        end

        -- ENCOUNTER_END feed: Injects localized encounter name into tooltip caches.
        -- Called from TryCounterService when a boss is killed in an instance.
        -- ENCOUNTER_END event args are NOT secret values (they're event payload, not API returns),
        -- so encounterName is always the correct localized string.
        -- This is the CRITICAL fallback for Midnight instances where:
        --   1. UnitGUID is secret (can't do GUID-based NPC lookup)
        --   2. EJ API might be restricted (can't build localizedNpcNameIndex)
        -- After the first kill, the localized boss name is cached → subsequent tooltip hovers work.
        self._feedEncounterKill = function(encounterName, encounterID)
            if not encounterName or encounterName == "" then return end
            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB then return end

            local encNpcIDs = sourceDB.encounters and sourceDB.encounters[encounterID]
            if not encNpcIDs then return end

            -- 1. Populate nameDropCache/nameNpcIDCache (used by METHOD 2 name lookup)
            local merged = {}
            local seen = {}
            local firstNpcID = nil
            for _, npcID in ipairs(encNpcIDs) do
                local npcDrops = sourceDB.npcs and sourceDB.npcs[npcID]
                if npcDrops then
                    if not firstNpcID then firstNpcID = npcID end
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
                nameDropCache[encounterName] = merged
                nameNpcIDCache[encounterName] = firstNpcID
            end

            -- 2. Also inject into localizedNpcNameIndex if it has been built already
            if localizedNpcNameIndex and not localizedNpcNameIndex[encounterName] then
                local valid = {}
                for _, npcID in ipairs(encNpcIDs) do
                    if sourceDB.npcs and sourceDB.npcs[npcID] then
                        valid[#valid + 1] = npcID
                    end
                end
                if #valid > 0 then
                    localizedNpcNameIndex[encounterName] = valid
                end
            end
        end

        -- Expose cache save for PLAYER_LOGOUT persistence of runtime-discovered names
        WarbandNexus._saveNpcNameCache = function()
            if not localizedNpcNameIndex then return end
            local count = 0
            for _ in pairs(localizedNpcNameIndex) do count = count + 1 end
            if count == 0 then return end
            SaveToCache(0)
        end

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

                -- Parse GameObject GUID: "GameObject-0-serverID-instanceID-zoneUID-objectID-spawnUID"
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

    self:Debug("GameTooltip hook initialized (TooltipDataProcessor)")
end

---Run self-diagnostic on tooltip systems. Called by /wn validate tooltip.
---Verifies localized npcNameIndex, lockout quest integration, and EJ API availability.
---@return table results { passed = bool, checks = { {name, status, detail} } }
function TooltipService:RunDiagnostics()
    local results = { passed = true, checks = {} }
    local function addCheck(name, ok, detail)
        results.checks[#results.checks + 1] = { name = name, status = ok, detail = detail }
        if not ok then results.passed = false end
    end

    -- 1. Check EJ API availability
    addCheck("EJ_GetEncounterInfo", EJ_GetEncounterInfo ~= nil, EJ_GetEncounterInfo and "Available" or "MISSING")
    addCheck("EJ_GetCreatureInfo", EJ_GetCreatureInfo ~= nil, EJ_GetCreatureInfo and "Available" or "MISSING")

    -- 2. Check localized npcNameIndex (force rebuild for fresh results)
    local sourceDB = ns.CollectibleSourceDB
    local index
    if self._forceRebuildIndex then
        index = self._forceRebuildIndex()
    elseif self._getLocalizedNpcNameIndex then
        index = self._getLocalizedNpcNameIndex()
    end
    if not index then index = {} end

    local totalNames = 0
    if index then
        for _ in pairs(index) do totalNames = totalNames + 1 end
    end

    -- Count how many names came from EJ vs static English
    local staticCount = 0
    if sourceDB and sourceDB.npcNameIndex then
        for _ in pairs(sourceDB.npcNameIndex) do staticCount = staticCount + 1 end
    end
    local ejNames = totalNames - staticCount
    if ejNames < 0 then ejNames = 0 end

    addCheck("localizedNpcNameIndex", totalNames > 0,
        totalNames .. " names (" .. ejNames .. " from EJ, " .. staticCount .. " static English)")

    -- 4. EJ spot-check: verify the localized index contains a known boss
    -- Check if "The Lich King" (or localized equivalent) is in the index
    -- NPC ID 36597 = The Lich King, should be reachable via encounters table
    local lichKingFound = false
    local lichKingName = nil
    if index then
        for name, npcIDs in pairs(index) do
            for _, npcID in ipairs(npcIDs) do
                if npcID == 36597 then
                    lichKingFound = true
                    lichKingName = name
                    break
                end
            end
            if lichKingFound then break end
        end
    end
    addCheck("EJ spot-check (Lich King npcID=36597)", lichKingFound,
        lichKingFound and ('"' .. lichKingName .. '"') or "Not found in index")

    -- 4. Verify lockoutQuests DB accessible
    local lockoutCount = 0
    if sourceDB and sourceDB.lockoutQuests then
        for _ in pairs(sourceDB.lockoutQuests) do lockoutCount = lockoutCount + 1 end
    end
    addCheck("lockoutQuests DB", lockoutCount > 0, lockoutCount .. " NPC lockout entries")

    -- 5. Check issecretvalue availability
    addCheck("issecretvalue API", issecretvalue ~= nil,
        issecretvalue and "Available (Midnight 12.0)" or "Not available (pre-12.0)")

    -- 6. Check C_Item.GetItemInfo availability
    addCheck("C_Item.GetItemInfo", C_Item and C_Item.GetItemInfo ~= nil,
        (C_Item and C_Item.GetItemInfo) and "Available" or "MISSING — using legacy GetItemInfo")

    -- 7. Check ENCOUNTER_END feed system
    addCheck("ENCOUNTER_END feed", self._feedEncounterKill ~= nil,
        self._feedEncounterKill and "Active — boss kills inject localized names into cache"
            or "NOT active — tooltip hook may not be initialized")

    return results
end

-- ============================================================================
-- CONCENTRATION TOOLTIP HOOK
-- ============================================================================

--[[
    Append cross-character concentration data to tooltips showing Concentration.
    
    Strategy (dual-layer, frame-path independent):
    
    1. TooltipDataProcessor (Currency type) — Blizzard's official modern API
       for post-processing tooltips. Since Concentration is a currency
       (concentrationCurrencyID), Blizzard uses SetCurrencyByID or similar
       to populate the tooltip. This fires reliably.
       
    2. GameTooltip:HookScript("OnShow") — Fallback for any non-currency
       tooltip path that still shows "Concentration" in the first line.
    
    Both are installed once at load time on GameTooltip (always available).
    No ProfessionsFrame frame-path discovery needed.
]]
local concentrationHookInstalled = false
local WN_CONCENTRATION_MARKER = "Warband Nexus - Concentration"

-- Check if we already injected our data into a tooltip
local function HasAlreadyInjected(tooltip)
    local numLines = tooltip:NumLines()
    for i = 2, numLines do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        if line then
            local lineText = line:GetText()
            if lineText and lineText:find("Warband Nexus") then
                return true
            end
        end
    end
    return false
end

-- Check if the tooltip's first line contains "Concentration"
local function IsConcentrationTooltip(tooltip)
    local firstLine = _G[tooltip:GetName() .. "TextLeft1"]
    if not firstLine then return false end
    local text = firstLine:GetText()
    if not text then return false end
    return text:find("Concentration") ~= nil
end

-- The actual function that appends concentration data to a visible tooltip
local function AppendConcentrationData(tooltip)
    if not WarbandNexus or not WarbandNexus.GetAllConcentrationData then return end

    local allConc = WarbandNexus:GetAllConcentrationData()
    if not allConc or not next(allConc) then return end

    tooltip:AddLine(" ")
    tooltip:AddLine(WN_CONCENTRATION_MARKER, 0.4, 0.8, 1)

    -- Sort profession names for consistent display
    local profNames = {}
    for profName in pairs(allConc) do
        profNames[#profNames + 1] = profName
    end
    table.sort(profNames)

    for _, profName in ipairs(profNames) do
        local entries = allConc[profName]
        tooltip:AddLine("  " .. profName, 1, 0.82, 0)

        for ei = 1, #entries do
            local entry = entries[ei]
            local cc = RAID_CLASS_COLORS[entry.classFile] or { r = 1, g = 1, b = 1 }
            local charColor = string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
            local timeStr = WarbandNexus:GetConcentrationTimeToFull(entry)
            local estimated = WarbandNexus:GetEstimatedConcentration(entry)
            local isFull = (estimated >= entry.max)

            local valueStr
            if isFull then
                valueStr = "|cff44ff44" .. entry.max .. " / " .. entry.max .. "|r  |cff44ff44(Full)|r"
            else
                valueStr = "|cffffffff~" .. estimated .. " / " .. entry.max .. "|r  |cffffffff(" .. timeStr .. ")|r"
            end

            tooltip:AddDoubleLine(
                "    " .. charColor .. entry.charName .. "|r",
                valueStr,
                1, 1, 1, 1, 1, 1
            )
        end
    end

    tooltip:Show()
end

function TooltipService:InstallConcentrationTooltipHook()
    if concentrationHookInstalled then return end

    -- ----------------------------------------------------------------
    -- Layer 1: TooltipDataProcessor for Currency tooltips (modern API)
    -- Concentration is a currency. When Blizzard calls
    -- GameTooltip:SetCurrencyByID(concentrationCurrencyID), this fires.
    -- ----------------------------------------------------------------
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum.TooltipDataType and Enum.TooltipDataType.Currency then
        local CURRENCY_TYPE = Enum.TooltipDataType.Currency
        TooltipDataProcessor.AddTooltipPostCall(CURRENCY_TYPE, function(tooltip, data)
            if tooltip ~= GameTooltip then return end
            if ns.Utilities and not ns.Utilities:IsModuleEnabled("professions") then return end
            if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return end
            if not IsConcentrationTooltip(tooltip) then return end
            if HasAlreadyInjected(tooltip) then return end
            -- Debug: log only when we actually match a Concentration tooltip
            if WarbandNexus and WarbandNexus.Debug then
                local line1 = _G["GameTooltipTextLeft1"]
                local text1 = line1 and line1:GetText() or "nil"
                WarbandNexus:Debug("[Conc Tooltip] Currency PostCall matched, line1=" .. tostring(text1))
            end

            local allConc = WarbandNexus and WarbandNexus.GetAllConcentrationData and WarbandNexus:GetAllConcentrationData()
            if WarbandNexus and WarbandNexus.Debug then
                local count = 0
                if allConc then for _ in pairs(allConc) do count = count + 1 end end
                WarbandNexus:Debug("[Conc Tooltip] Matched! allConc professions=" .. count)
            end

            pcall(AppendConcentrationData, tooltip)
        end)
    end

    -- ----------------------------------------------------------------
    -- Layer 2: GameTooltip OnShow fallback
    -- Catches any non-currency code path (custom SetOwner + AddLine).
    -- ----------------------------------------------------------------
    GameTooltip:HookScript("OnShow", function(tooltip)
        -- Guard: skip when professions module is disabled
        if ns.Utilities and not ns.Utilities:IsModuleEnabled("professions") then return end
        if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return end
        if not IsConcentrationTooltip(tooltip) then return end
        if HasAlreadyInjected(tooltip) then return end

        if WarbandNexus and WarbandNexus.Debug then
            local allConc = WarbandNexus.GetAllConcentrationData and WarbandNexus:GetAllConcentrationData()
            local count = 0
            if allConc then for _ in pairs(allConc) do count = count + 1 end end
            WarbandNexus:Debug("[Conc Tooltip] OnShow matched! allConc professions=" .. count)
        end

        pcall(AppendConcentrationData, tooltip)
    end)

    concentrationHookInstalled = true
    if self.Debug then
        self:Debug("Concentration tooltip hook installed (TooltipDataProcessor + OnShow dual strategy)")
    end
end

-- Install the hook immediately at load time — GameTooltip is always available.
TooltipService:InstallConcentrationTooltipHook()

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
