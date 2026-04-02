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
    Return tooltip stat lines for an item (for use under profession equipment in custom tooltips).
    Skips title line; returns left/right lines with colors. Safe for secret values (Midnight).
    @param itemLink string|nil - Item hyperlink (preferred)
    @param itemID number|nil - Item ID fallback when itemLink is nil
    @return table - Array of { left, right, leftColor, rightColor }
]]
function TooltipService:GetItemTooltipStatLines(itemLink, itemID)
    if not C_TooltipInfo then return {} end
    local tooltipData
    if itemLink and type(itemLink) == "string" and (not issecretvalue or not issecretvalue(itemLink)) then
        if C_TooltipInfo.GetHyperlink then
            local ok, result = pcall(C_TooltipInfo.GetHyperlink, itemLink)
            if ok and result then tooltipData = result end
        end
    end
    if not tooltipData and itemID and C_TooltipInfo.GetItemByID then
        local ok, result = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok and result then tooltipData = result end
    end
    if not tooltipData or not tooltipData.lines then return {} end
    if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, tooltipData) end
    local out = {}
    for i = 2, math.min(#tooltipData.lines, 12) do
        local line = tooltipData.lines[i]
        if not line then break end
        local left = line.leftText
        local right = line.rightText
        if issecretvalue then
            if left and issecretvalue(left) then left = nil end
            if right and issecretvalue(right) then right = nil end
        end
        left = (left and tostring(left):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        right = (right and tostring(right):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        if left ~= "" or right ~= "" then
            local lc = line.leftColor
            local rc = line.rightColor
            local leftColor = lc and { lc.r or 1, lc.g or 1, lc.b or 1 } or { 0.85, 0.85, 0.85 }
            local rightColor = rc and { rc.r or 1, rc.g or 1, rc.b or 1 } or { 0.75, 0.75, 0.75 }
            out[#out + 1] = { left = left, right = right, leftColor = leftColor, rightColor = rightColor }
        end
    end
    return out
end

-- Slot name mapping for profession equipment (itemEquipLoc from GetItemInfo)
local INV_TYPE_TO_LABEL = {
    INVTYPE_HEAD = "Head",
    INVTYPE_NECK = "Neck",
    INVTYPE_SHOULDER = "Shoulder",
    INVTYPE_CHEST = "Chest",
    INVTYPE_ROBE = "Chest",
    INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet",
    INVTYPE_WRIST = "Wrist",
    INVTYPE_HAND = "Hands",
    INVTYPE_FINGER = "Finger",
    INVTYPE_TRINKET = "Trinket",
    INVTYPE_CLOAK = "Back",
    INVTYPE_WEAPONMAINHAND = "Weapon",
    INVTYPE_WEAPONOFFHAND = "Off Hand",
    INVTYPE_HOLDABLE = "Held",
    INVTYPE_2HWEAPON = "Two-Hand",
    INVTYPE_PROFESSION_GEAR = nil,  -- resolved from tooltip (Head/Chest/etc.)
    INVTYPE_PROFESSION_TOOL = "Tool",
}
-- Tooltip slot patterns (e.g. "Unique-Equipped: Head (1)") when equipLoc is PROFESSION_GEAR
local TOOLTIP_SLOT_PATTERNS = { "Head", "Chest", "Shoulder", "Hands", "Legs", "Feet", "Waist", "Wrist", "Back", "Neck", "Tool" }

--[[
    Return only item level, stats, and equip-effect lines for profession equipment tooltips.
    Plus a first line for slot type (Tool / Head / Chest / etc.).
    @param itemLink string|nil
    @param itemID number|nil
    @param slotKey string "tool" | "accessory1" | "accessory2"
    @return table - Array of { left, right, leftColor, rightColor }
]]
function TooltipService:GetItemTooltipSummaryLines(itemLink, itemID, slotKey)
    local out = {}
    local slotLabel = (slotKey == "tool") and "Tool" or "Accessory"

    -- Load tooltip data first (needed for slot inference when equipLoc is PROFESSION_GEAR)
    local tooltipData
    if C_TooltipInfo then
        if itemLink and type(itemLink) == "string" and (not issecretvalue or not issecretvalue(itemLink)) and C_TooltipInfo.GetHyperlink then
            local ok, result = pcall(C_TooltipInfo.GetHyperlink, itemLink)
            if ok and result then tooltipData = result end
        end
        if not tooltipData and itemID and C_TooltipInfo.GetItemByID then
            local ok, result = pcall(C_TooltipInfo.GetItemByID, itemID)
            if ok and result then tooltipData = result end
        end
    end
    if tooltipData and tooltipData.lines and TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, tooltipData)
    end

    -- Resolve slot: equipLoc from API, or from tooltip when INVTYPE_PROFESSION_GEAR
    if itemID or itemLink then
        local equipLoc = nil
        if C_Item and C_Item.GetItemInfo then
            local link = itemLink or (itemID and ("item:" .. tostring(itemID))) or nil
            local ok, name, _, _, _, _, _, _, eq = pcall(C_Item.GetItemInfo, link or itemID)
            if ok and eq and type(eq) == "string" and eq ~= "" then equipLoc = eq end
        end
        if (not equipLoc or equipLoc == "") and C_Item and C_Item.GetItemInfoInstant and itemID then
            local ok2, _, _, _, eqInst = pcall(C_Item.GetItemInfoInstant, itemID)
            if ok2 and eqInst and type(eqInst) == "string" and eqInst ~= "" then equipLoc = eqInst end
        end
        if equipLoc and equipLoc ~= "" then
            local mapped = INV_TYPE_TO_LABEL[equipLoc]
            if mapped then
                slotLabel = mapped
            elseif equipLoc:find("PROFESSION_GEAR") or equipLoc:find("Profession") then
                -- Infer from tooltip (e.g. "Unique-Equipped: Head (1)" or "Head")
                if tooltipData and tooltipData.lines then
                    for i = 1, math.min(#tooltipData.lines, 5) do
                        local line = tooltipData.lines[i]
                        if line then
                            local left = line.leftText
                            local right = line.rightText
                            if issecretvalue then
                                if left and issecretvalue(left) then left = nil end
                                if right and issecretvalue(right) then right = nil end
                            end
                            left = (left and tostring(left)) or ""
                            right = (right and tostring(right)) or ""
                            for _, pat in ipairs(TOOLTIP_SLOT_PATTERNS) do
                                local escaped = pat:gsub("%%", "%%%%")
                                local word = "[%s%(:]" .. escaped .. "[%s%(]"
                                local start = "^" .. escaped .. "[%s%(]"
                                if (left ~= "" and (left:find(word) or left:find(start) or left == pat)) or (right ~= "" and (right:find(word) or right:find(start) or right == pat)) then
                                    slotLabel = pat
                                    break
                                end
                            end
                            if slotLabel ~= "Accessory" and slotLabel ~= "Tool" then break end
                        end
                    end
                end
            else
                slotLabel = INV_TYPE_TO_LABEL[equipLoc] or equipLoc:gsub("INVTYPE_", ""):gsub("(%l)(%u)", "%1 %2") or "Accessory"
            end
        end
    end
    out[1] = { left = slotLabel, right = "", leftColor = {0.7, 0.7, 0.9}, rightColor = {0.75, 0.75, 0.75} }

    if not tooltipData or not tooltipData.lines then return out end

    for i = 2, math.min(#tooltipData.lines, 14) do
        local line = tooltipData.lines[i]
        if not line then break end
        local left = line.leftText
        local right = line.rightText
        if issecretvalue then
            if left and issecretvalue(left) then left = nil end
            if right and issecretvalue(right) then right = nil end
        end
        left = (left and tostring(left):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        right = (right and tostring(right):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        if left ~= "" or right ~= "" then
            local combined = (left .. " " .. right):lower()
            -- Exclude: binding, unique-equipped, "Alchemy Accessory" type, empty filler
            if combined:find("binds when") or combined:find("unique%-equipped") or combined:find("when equipped") then
                -- skip
            else
                -- Include only: (1) Item Level, (2) stat lines (+Number), (3) equip effect (+X ... Skill). Exclude Requires Level.
                local isItemLevel = left:find("Item Level") or right:find("Item Level")
                local isStat = left:find("^%+%d") or right:find("^%+%d")
                local isEquipEffect = left:find("%+%d") and left:find("Skill")
                if isItemLevel or isStat or isEquipEffect then
                    local lc = line.leftColor
                    local rc = line.rightColor
                    out[#out + 1] = {
                        left = left,
                        right = right,
                        leftColor = lc and { lc.r or 1, lc.g or 1, lc.b or 1 } or { 0.85, 0.85, 0.85 },
                        rightColor = rc and { rc.r or 1, rc.g or 1, rc.b or 1 } or { 0.75, 0.75, 0.75 },
                    }
                end
            end
        end
    end
    return out
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

    -- Progress details (Current / Max / Season / Remaining) for key currencies.
    do
        local explicitCharKey = data.charKey
        local charKey = explicitCharKey or (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()) or nil
        local currencyData = nil
        if WarbandNexus and WarbandNexus.GetCurrencyData and charKey then
            currencyData = WarbandNexus:GetCurrencyData(currencyID, charKey)
        end

        -- C_CurrencyInfo quantities / totalEarned are for the logged-in character only.
        -- When the tooltip is for another row (explicit charKey), never merge those API values.
        local canonRow = nil
        local canonCur = nil
        if ns.Utilities then
            if explicitCharKey and ns.Utilities.GetCanonicalCharacterKey then
                canonRow = ns.Utilities:GetCanonicalCharacterKey(explicitCharKey) or explicitCharKey
            elseif explicitCharKey then
                canonRow = explicitCharKey
            end
            if ns.Utilities.GetCharacterKey then
                canonCur = ns.Utilities:GetCharacterKey()
            end
            if canonCur and ns.Utilities.GetCanonicalCharacterKey then
                canonCur = ns.Utilities:GetCanonicalCharacterKey(canonCur) or canonCur
            end
        end
        local function normKey(k)
            return (k and k:gsub("%s+", "")) or ""
        end
        local useLiveCurrencyNumbers = (not explicitCharKey)
            or (canonRow and canonCur and normKey(canonRow) == normKey(canonCur))

        local qty
        if currencyData and currencyData.quantity ~= nil then
            qty = currencyData.quantity
        elseif useLiveCurrencyNumbers then
            qty = info.quantity or 0
        else
            qty = 0
        end
        local maxQty = (currencyData and currencyData.maxQuantity) or info.maxQuantity or 0
        local totalEarned = currencyData and currencyData.totalEarned
        if totalEarned == nil and useLiveCurrencyNumbers then
            if WarbandNexus and WarbandNexus.GetCurrencyProgressEarnedFromAPI then
                totalEarned = WarbandNexus:GetCurrencyProgressEarnedFromAPI(currencyID)
            end
            if totalEarned == nil and info.totalEarned ~= nil then
                if not (issecretvalue and issecretvalue(info.totalEarned)) then
                    totalEarned = tonumber(info.totalEarned)
                end
            end
        end
        local seasonMax = currencyData and currencyData.seasonMax
        if (seasonMax == nil or type(seasonMax) ~= "number" or seasonMax <= 0)
            and type(info.maxQuantity) == "number" and info.maxQuantity > 0
            and info.useTotalEarnedForMaxQty then
            seasonMax = info.maxQuantity
        end
        local hasSeasonProgress = (type(seasonMax) == "number" and seasonMax > 0)
        local teNum = (totalEarned ~= nil and type(totalEarned) == "number") and totalEarned or nil

        if hasSeasonProgress or (type(maxQty) == "number" and maxQty > 0) then
            local fmtNumber = ns.UI_FormatNumber or function(n) return tostring(n or 0) end
            local currentLabel = (ns.L and ns.L["CURRENT_ENTRIES_LABEL"]) or "Current:"
            local seasonLabel = (ns.L and ns.L["SEASON"]) or "Season"
            local cappedText = CAPPED or "Capped"
            local remainingSuffix = (ns.L and ns.L["VAULT_REMAINING_SUFFIX"]) or "remaining"
            frame:AddSpacer(6)

            if hasSeasonProgress then
                local teForSeason = (teNum ~= nil) and teNum or 0
                local remSeason = math.max((seasonMax or 0) - teForSeason, 0)
                frame:AddLine(string.format("%s %s", currentLabel, fmtNumber(qty)), 1, 1, 1, false)
                frame:AddLine(string.format("%s: %s / %s", seasonLabel, fmtNumber(teForSeason), fmtNumber(seasonMax or 0)), 1, 1, 1, false)
                if remSeason > 0 then
                    frame:AddLine(string.format("%s %s", fmtNumber(remSeason), remainingSuffix), 0.5, 1, 0.5, false)
                else
                    frame:AddLine(cappedText, 1, 0.35, 0.35, false)
                end
            else
                -- No season cap: single Current / max line + remaining (weekly-style cap only)
                local cap = maxQty
                local rem = math.max((cap or 0) - (qty or 0), 0)
                frame:AddLine(string.format("%s / %s", fmtNumber(qty), fmtNumber(cap or 0)), 1, 1, 1, false)
                if rem > 0 then
                    frame:AddLine(string.format("%s %s", fmtNumber(rem), remainingSuffix), 0.5, 1, 0.5, false)
                else
                    frame:AddLine(cappedText, 1, 0.35, 0.35, false)
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
-- SHARED COLLECTIBLE DROP LINES (used by Unit and Item tooltip hooks)
-- ============================================================================

---Inject collectible drop lines into a GameTooltip.
---Shows header, item hyperlinks, collected/repeatable status, and try counts.
---Shared across NPC (Unit) and Container (Item) tooltip hooks.
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

    -- When locked out (already killed this period), show why drops are gray
    if isLockedOut then
        local lockoutHint = (ns.L and ns.L["TOOLTIP_NO_LOOT_UNTIL_RESET"]) or "No loot until next reset"
        tooltip:AddLine("|cff666666" .. lockoutHint .. "|r", 0.6, 0.6, 0.6)
    end

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
            -- Mounts: epic (purple); others: legacy orange fallback
            local fallbackColor = (drop.type == "mount") and "a335ee" or "ff8000"
            itemLink = "|cff" .. fallbackColor .. "[" .. (drop.name or ((ns.L and ns.L["TOOLTIP_UNKNOWN"]) or "Unknown")) .. "]|r"
        elseif drop.type == "mount" then
            -- Force epic (purple) for mount names in tooltip
            itemLink = itemLink:gsub("^|c%x%x%x%x%x%x%x%x%x", "|cffa335ee")
        end

        -- Collection status check
        local collected = false
        local collectibleID = nil

        if drop.type == "item" then
            -- Generic items (e.g. Miscellaneous Mechanica): collectibleID == itemID, never "collected"
            collectibleID = drop.itemID
            collected = false
            
            -- QUEST STARTER HANDLING: If this item starts a quest for a mount/pet/toy,
            -- check if the FINAL collectible is already obtained
            if drop.questStarters and #drop.questStarters > 0 then
                local questReward = drop.questStarters[1]
                if questReward and questReward.type then
                    if questReward.type == "mount" then
                        if C_MountJournal and C_MountJournal.GetMountFromItem then
                            local mountID = C_MountJournal.GetMountFromItem(questReward.itemID)
                            if issecretvalue and mountID and issecretvalue(mountID) then
                                mountID = nil
                            end
                            if mountID then
                                local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                                if not (issecretvalue and isCollected and issecretvalue(isCollected)) then
                                    collected = isCollected == true
                                end
                            end
                        end
                    elseif questReward.type == "pet" then
                        if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                            local _, _, _, _, _, _, _, _, _, _, _, _, specID = C_PetJournal.GetPetInfoByItemID(questReward.itemID)
                            if issecretvalue and specID and issecretvalue(specID) then
                                specID = nil
                            end
                            if specID then
                                local numCollected = C_PetJournal.GetNumCollectedInfo(specID)
                                if not (issecretvalue and numCollected and issecretvalue(numCollected)) then
                                    collected = numCollected and numCollected > 0
                                end
                            end
                        end
                    elseif questReward.type == "toy" then
                        if PlayerHasToy then
                            local hasToy = PlayerHasToy(questReward.itemID)
                            if not (issecretvalue and hasToy and issecretvalue(hasToy)) then
                                collected = hasToy == true
                            end
                        end
                    end
                end
            end
        elseif drop.type == "mount" then
            if C_MountJournal and C_MountJournal.GetMountFromItem then
                collectibleID = C_MountJournal.GetMountFromItem(drop.itemID)
                -- Midnight 12.0: GetMountFromItem can return secret value; still check collected via pcall
                if collectibleID then
                    local ok, _, _, _, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, collectibleID)
                    if ok and isCollected and not (issecretvalue and issecretvalue(isCollected)) then
                        collected = isCollected == true
                    end
                    if issecretvalue and issecretvalue(collectibleID) then
                        collectibleID = nil  -- do not use secret as key for try count / display
                    end
                end
            end
        elseif drop.type == "pet" then
            if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                -- speciesID is the 13th return value, NOT the 1st (which is pet name)
                local _, _, _, _, _, _, _, _, _, _, _, _, specID = C_PetJournal.GetPetInfoByItemID(drop.itemID)
                collectibleID = specID
                if collectibleID then
                    local ok, numCollected = pcall(C_PetJournal.GetNumCollectedInfo, collectibleID)
                    if ok and numCollected and not (issecretvalue and issecretvalue(numCollected)) then
                        collected = numCollected > 0
                    end
                    if issecretvalue and issecretvalue(specID) then
                        collectibleID = nil
                    end
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
        -- If the DB sets repeatable explicitly (true/false), honor it — do not override with global index
        -- (avoids wrong "Repeatable" UI when another source or stale index disagrees).
        local isRepeatable = drop.repeatable
        local isGuaranteed = drop.guaranteed
        if not isGuaranteed and WarbandNexus and WarbandNexus.IsGuaranteedCollectible then
            isGuaranteed = WarbandNexus:IsGuaranteedCollectible(drop.type, collectibleID or drop.itemID)
        end
        if isRepeatable == nil and WarbandNexus and WarbandNexus.IsRepeatableCollectible then
            isRepeatable = WarbandNexus:IsRepeatableCollectible(drop.type, collectibleID or drop.itemID)
        end

        -- Try count (do not show for 100% guaranteed drops or when module disabled)
        local tryCount = 0
        local tryCounterEnabled = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
            and (not WarbandNexus.db.profile.modulesEnabled or WarbandNexus.db.profile.modulesEnabled.tryCounter ~= false)
        if tryCounterEnabled and not isGuaranteed and WarbandNexus and WarbandNexus.GetTryCount then
            if collectibleID then
                tryCount = WarbandNexus:GetTryCount(drop.type, collectibleID)
            end
            if tryCount == 0 then
                tryCount = WarbandNexus:GetTryCount(drop.type, drop.itemID)
            end
        end

        -- Build right-side status text
        -- Collected items: green checkmark prepended to item name, no right text.
        -- Repeatable items: always show try counter on the right.
        -- Locked out: everything gray.
        local rightText
        -- (showCollectedLine removed — checkmark is inline with item name)
        local attemptsWord = (ns.L and ns.L["TOOLTIP_ATTEMPTS"]) or "attempts"
        -- collectedWord removed — replaced by inline checkmark icon
        local guaranteedWord = (ns.L and ns.L["TOOLTIP_100_DROP"]) or "100% Drop"
        if isRepeatable then
            local attemptsColor = isLockedOut and "666666" or "ffff00"
            rightText = "|cff" .. attemptsColor .. tryCount .. " " .. attemptsWord .. "|r"
            -- collected status is shown via inline checkmark on the item line
        elseif isLockedOut and not collected then
            local attemptsColor = isLockedOut and "666666" or "888888"
            rightText = "|cff" .. attemptsColor .. tryCount .. " " .. attemptsWord .. "|r"
        elseif collected then
            rightText = ""
        elseif isGuaranteed then
            rightText = "|cff00ff00" .. guaranteedWord .. "|r"
        elseif tryCount > 0 then
            rightText = "|cffffff00" .. tryCount .. " " .. attemptsWord .. "|r"
        else
            -- Default 0 when no try count (non-repeatable, not collected, not guaranteed)
            rightText = "|cff8888880 " .. attemptsWord .. "|r"
        end

        -- When locked out and not collected, dim the item link to gray
        local displayLink = itemLink
        if isLockedOut and not collected then
            local plainName = drop.name or ((ns.L and ns.L["TOOLTIP_UNKNOWN"]) or "Unknown")
            if itemLink then
                local linkName = itemLink:match("%[(.-)%]")
                if linkName then plainName = linkName end
            end
            displayLink = "|cff666666[" .. plainName .. "]|r"
        end

        -- Prepend green checkmark for collected items (inline texture for reliable rendering)
        if collected then
            displayLink = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t " .. displayLink
        end

        -- Append yellow (Planned) for items in the player's Plans list
        local isPlanned = false
        if WarbandNexus then
            if drop.type == "mount" and collectibleID and WarbandNexus.IsMountPlanned then
                isPlanned = WarbandNexus:IsMountPlanned(collectibleID)
            elseif drop.type == "pet" and collectibleID and WarbandNexus.IsPetPlanned then
                isPlanned = WarbandNexus:IsPetPlanned(collectibleID)
            elseif (drop.type == "toy" or drop.type == "item") and drop.itemID and WarbandNexus.IsItemPlanned then
                isPlanned = WarbandNexus:IsItemPlanned(drop.type, drop.itemID)
            end
        end
        if isPlanned then
            local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
            displayLink = displayLink .. " |cffffcc00(" .. plannedWord .. ")|r"
        end

        tooltip:AddDoubleLine(
            displayLink,
            rightText,
            1, 1, 1,  -- left color (overridden by hyperlink color codes)
            1, 1, 1   -- right color (overridden by inline color codes)
        )

        -- Show yields below item-type drops (e.g. Crackling Shard → Alunira)
        if drop.yields then
            for _, yield in ipairs(drop.yields) do
                local yieldCollected = false
                if yield.type == "mount" and yield.itemID then
                    if C_MountJournal and C_MountJournal.GetMountFromItem then
                        local mountID = C_MountJournal.GetMountFromItem(yield.itemID)
                        if mountID and not (issecretvalue and issecretvalue(mountID)) then
                            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                            if not (issecretvalue and isCollected and issecretvalue(isCollected)) then
                                yieldCollected = isCollected == true
                            end
                        end
                    end
                elseif yield.type == "pet" and yield.itemID then
                    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                        local _, _, _, _, _, _, _, _, _, _, _, _, specID = C_PetJournal.GetPetInfoByItemID(yield.itemID)
                        if specID and not (issecretvalue and issecretvalue(specID)) then
                            local numCollected = C_PetJournal.GetNumCollectedInfo(specID)
                            if not (issecretvalue and numCollected and issecretvalue(numCollected)) then
                                yieldCollected = numCollected and numCollected > 0
                            end
                        end
                    end
                elseif yield.type == "toy" and yield.itemID then
                    if PlayerHasToy then
                        local hasToy = PlayerHasToy(yield.itemID)
                        if not (issecretvalue and hasToy and issecretvalue(hasToy)) then
                            yieldCollected = hasToy == true
                        end
                    end
                end

                -- Check if yield is planned
                local yieldPlanned = false
                if WarbandNexus then
                    if yield.type == "mount" and yield.itemID and WarbandNexus.IsMountPlanned then
                        local yMountID = C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(yield.itemID)
                        if yMountID and not (issecretvalue and issecretvalue(yMountID)) then
                            yieldPlanned = WarbandNexus:IsMountPlanned(yMountID)
                        end
                    elseif yield.type == "pet" and yield.itemID and WarbandNexus.IsPetPlanned then
                        if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                            local _, _, _, _, _, _, _, _, _, _, _, _, ySpecID = C_PetJournal.GetPetInfoByItemID(yield.itemID)
                            if ySpecID and not (issecretvalue and issecretvalue(ySpecID)) then
                                yieldPlanned = WarbandNexus:IsPetPlanned(ySpecID)
                            end
                        end
                    elseif yield.type == "toy" and yield.itemID and WarbandNexus.IsItemPlanned then
                        yieldPlanned = WarbandNexus:IsItemPlanned("toy", yield.itemID)
                    end
                end

                local yieldIcon = yieldCollected
                    and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
                    or  "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
                local yieldColor = yieldCollected and "ff00ff00" or "ff999999"
                local typeLabel = yield.type == "mount" and "Mount"
                    or yield.type == "pet" and "Pet"
                    or yield.type == "toy" and "Toy"
                    or ""
                local yieldSuffix = ""
                if yieldPlanned then
                    local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
                    yieldSuffix = " |cffffcc00(" .. plannedWord .. ")|r"
                end
                tooltip:AddLine(
                    "   " .. yieldIcon .. " |c" .. yieldColor .. yield.name .. " (" .. typeLabel .. ")|r" .. yieldSuffix,
                    1, 1, 1
                )
            end
        end
    end

    tooltip:Show()
end

-- ============================================================================
-- ITEM DATA PRE-CACHE (eliminates first-hover tooltip delay)
-- ============================================================================

--[[
    Pre-request all item data from CollectibleSourceDB so that GetItemInfo
    returns instantly when the user hovers over an NPC / container / object.
    Without this, the first hover triggers an async server request and the
    tooltip renders with a fallback name instead of a quality-colored link.
    Batched over multiple frames to avoid FPS spikes.
]]
function TooltipService:PreCacheCollectibleItems()
    local sourceDB = ns.CollectibleSourceDB
    if not sourceDB then return end

    local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID
    if not RequestLoad then return end

    -- Collect unique item IDs from all source tables
    local itemIDs = {}
    local seen = {}
    local function Collect(tbl)
        if not tbl then return end
        for _, drops in pairs(tbl) do
            if type(drops) == "table" then
                for i = 1, #drops do
                    local d = drops[i]
                    if d and d.itemID and not seen[d.itemID] then
                        seen[d.itemID] = true
                        itemIDs[#itemIDs + 1] = d.itemID
                    end
                end
            end
        end
    end

    Collect(sourceDB.npcs)
    Collect(sourceDB.containers)
    Collect(sourceDB.objects)
    Collect(sourceDB.fishing)

    if #itemIDs == 0 then return end

    -- Batch-request: 20 items per frame tick to stay under budget
    local BATCH_SIZE = 20
    local idx = 1
    local function ProcessBatch()
        local batchEnd = math.min(idx + BATCH_SIZE - 1, #itemIDs)
        for i = idx, batchEnd do
            pcall(RequestLoad, itemIDs[i])
        end
        idx = batchEnd + 1
        if idx <= #itemIDs then
            C_Timer.After(0, ProcessBatch)
        else
            self:Debug("Pre-cached " .. #itemIDs .. " collectible item IDs for tooltip readiness")
        end
    end

    ProcessBatch()
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
        if not (WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile) then
            return
        end
        local showTooltipItemCount = WarbandNexus.db.profile.showTooltipItemCount
        if showTooltipItemCount == nil then
            -- Backward compatibility for older profiles that only had showItemCount.
            showTooltipItemCount = WarbandNexus.db.profile.showItemCount
        end
        if not showTooltipItemCount then
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
                    warbandIcon .. " " .. ((ns.L and ns.L["TOOLTIP_WARBAND_BANK"]) or "Warband Bank"),
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
                    -- Only show characters that actually have this item
                    if char.bankCount > 0 or char.bagCount > 0 then
                        local cc = RAID_CLASS_COLORS[char.classFile] or { r = 1, g = 1, b = 1 }
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
                end

                if not isShift and #details.characters > 5 then
                    tooltip:AddLine((ns.L and ns.L["TOOLTIP_HOLD_SHIFT"]) or "  Hold [Shift] for full list", 0.5, 0.5, 0.5)
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

    -- ================================================================
    -- ITEM TOOLTIP: "(Planned)" indicator for items in the Plans list
    -- Checks mount/pet/toy/item plans and appends yellow text
    -- ================================================================
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not WarbandNexus then return end
        if not tooltip or not tooltip.AddLine then return end

        local itemID = data and data.id
        if not itemID then return end

        local planned = false

        -- Check direct itemID (covers toys, generic items, any plan with itemID)
        if not planned and WarbandNexus.IsItemPlanned then
            planned = WarbandNexus:IsItemPlanned(nil, itemID)
        end

        -- Check mount (itemID → mountID)
        if not planned and WarbandNexus.IsMountPlanned
            and C_MountJournal and C_MountJournal.GetMountFromItem then
            local mountID = C_MountJournal.GetMountFromItem(itemID)
            if mountID and mountID > 0 and not (issecretvalue and issecretvalue(mountID)) then
                planned = WarbandNexus:IsMountPlanned(mountID)
            end
        end

        -- Check pet (itemID → speciesID)
        if not planned and WarbandNexus.IsPetPlanned
            and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
            local _, _, _, _, _, _, _, _, _, _, _, _, specID = C_PetJournal.GetPetInfoByItemID(itemID)
            if specID and specID > 0 and not (issecretvalue and issecretvalue(specID)) then
                planned = WarbandNexus:IsPetPlanned(specID)
            end
        end

        if planned then
            local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
            tooltip:AddLine("|cffffcc00(" .. plannedWord .. ")|r")
            tooltip:Show()
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

        -- GameObject IDs that WoW sometimes shows with Unit (Creature) tooltip. Do not inject
        -- collectible drops on these (they are objects, not NPCs that drop mounts/pets).
        local UNIT_TOOLTIP_OBJECT_IDS = {
            [209781] = true,  -- Empowered Restoration Stone (Midnight)
        }
        -- Unit names that are known GameObjects (name-fallback path). Do not show drops.
        local UNIT_TOOLTIP_OBJECT_NAMES = {
            ["Empowered Restoration Stone"] = true,
        }

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
            local zoneDrops = nil      -- Zone-wide drops to merge

            -- Helper: Get current zone's drops (if any)
            -- Returns: drops, raresOnly (boolean), hostileOnly (boolean)
            local function GetCurrentZoneDrops()
                if not sourceDB.zones then return nil, false, false end
                local rawMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                local mapID = (rawMapID and (not issecretvalue or not issecretvalue(rawMapID))) and rawMapID or nil
                while mapID and mapID > 0 do
                    local zData = sourceDB.zones[mapID]
                    if zData then
                        -- New format: { drops = {...}, raresOnly = true, hostileOnly = true }
                        if zData.drops then
                            return zData.drops, zData.raresOnly == true, zData.hostileOnly == true
                        end
                        -- Old format: direct array of drops
                        return zData, false, false
                    end
                    local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
                    local nextID = mapInfo and mapInfo.parentMapID
                    mapID = (nextID and (not issecretvalue or not issecretvalue(nextID))) and nextID or nil
                end
                return nil, false, false
            end

            -- Helper: Check if mouseover unit is rare/elite (for raresOnly zones)
            local function IsMouseoverRareOrElite()
                local ok, classification = pcall(UnitClassification, "mouseover")
                if not ok or not classification then return false end
                if issecretvalue and issecretvalue(classification) then return false end
                -- "rare", "rareelite", "worldboss" are rare-quality units
                return classification == "rare" or classification == "rareelite" or classification == "worldboss"
            end

            -- Helper: Check if mouseover unit is attackable (for hostileOnly zones)
            local function IsMouseoverAttackable()
                local ok, canAttack = pcall(UnitCanAttack, "player", "mouseover")
                if ok and canAttack == true then return true end
                -- Dead units are no longer attackable; check if it's a lootable corpse
                local okDead, isDead = pcall(UnitIsDead, "mouseover")
                if okDead and isDead == true then
                    local okReact, reaction = pcall(UnitReaction, "mouseover", "player")
                    if okReact and type(reaction) == "number" and reaction <= 4 then return true end
                end
                return false
            end

            -- In instances, do not show zone-wide drops on unit tooltips (avoids e.g. "Mount"
            -- appearing on objects like Empowered Restoration Stone that use Unit tooltip).
            local function ClearZoneDropsInInstance()
                if not zoneDrops or #zoneDrops == 0 then return end
                local inInstance = IsInInstance and IsInInstance()
                if inInstance and issecretvalue and issecretvalue(inInstance) then inInstance = nil end
                if inInstance then zoneDrops = nil end
            end

            -- METHOD 1: GUID-based lookup (works outside instances / when not secret)
            local ok, guid = pcall(UnitGUID, "mouseover")
            if ok and guid and not (issecretvalue and issecretvalue(guid)) then
                local unitType, _, _, _, _, rawID = strsplit("-", guid)
                if unitType == "Creature" or unitType == "Vehicle" then
                    local npcID = tonumber(rawID)
                    if npcID then
                        -- Skip known GameObjects that WoW shows as Unit tooltip (e.g. Empowered Restoration Stone)
                        if UNIT_TOOLTIP_OBJECT_IDS[npcID] then
                            drops = nil
                            zoneDrops = nil
                        else
                        drops = sourceDB.npcs[npcID]
                        if drops then resolvedNpcID = npcID end
                        -- Check for zone-wide drops (e.g., Midnight zone rare mounts)
                        local zRaresOnly, zHostileOnly
                        zoneDrops, zRaresOnly, zHostileOnly = GetCurrentZoneDrops()
                        -- If zone is raresOnly, only show on rare/elite units
                        if zoneDrops and zRaresOnly and not IsMouseoverRareOrElite() then
                            zoneDrops = nil
                        end
                        -- If zone is hostileOnly, only show on attackable units (not friendly NPCs/vendors)
                        if zoneDrops and zHostileOnly and not IsMouseoverAttackable() then
                            zoneDrops = nil
                        end
                        -- In instances, never show zone drops on unit tooltip (e.g. Empowered Restoration Stone)
                        ClearZoneDropsInInstance()
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
                end
                -- If no NPC drops and no zone drops, exit early
                if not drops and not zoneDrops then return end
            end

            -- METHOD 2: Name-based fallback (Midnight 12.0 - GUID is secret in instances)
            -- Only enter if we have neither NPC drops nor zone drops from GUID lookup
            if not drops and not zoneDrops then
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
                -- Skip known GameObject names (e.g. Empowered Restoration Stone)
                if UNIT_TOOLTIP_OBJECT_NAMES[unitName] then return end

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

                -- Name-fallback path: we cannot distinguish NPC vs GameObject (e.g. Empowered
                -- Restoration Stone uses Unit tooltip but is an object). Do NOT add zone drops here,
                -- or objects in Harandar etc. would show "Rootstalker Grimlynx / Vibrant Petalwing".
                -- Zone drops are only shown in METHOD 1 when GUID confirms Creature/Vehicle.
                zoneDrops = nil

                if (not drops or #drops == 0) and not zoneDrops then return end
            end

            -- Merge zone drops with NPC drops (if any)
            local finalDrops = drops
            if zoneDrops and #zoneDrops > 0 then
                if not finalDrops or #finalDrops == 0 then
                    finalDrops = zoneDrops
                else
                    -- Merge: NPC drops first, then zone drops (deduplicated)
                    local merged = {}
                    local seen = {}
                    for i = 1, #finalDrops do
                        local d = finalDrops[i]
                        if not seen[d.itemID] then
                            seen[d.itemID] = true
                            merged[#merged + 1] = d
                        end
                    end
                    for i = 1, #zoneDrops do
                        local d = zoneDrops[i]
                        if not seen[d.itemID] then
                            seen[d.itemID] = true
                            merged[#merged + 1] = d
                        end
                    end
                    finalDrops = merged
                end
            end

            -- Use shared rendering function (pass npcID for lockout checking)
            InjectCollectibleDropLines(tooltip, finalDrops, resolvedNpcID)
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
        -- When encounterID is secret (Midnight), caller may pass npcIDsOverride (array of npcIDs)
        -- so tooltip cache is still populated by name. After the first kill, the localized
        -- boss name is cached → subsequent tooltip hovers work.
        self._feedEncounterKill = function(encounterName, encounterID, npcIDsOverride)
            if not encounterName or encounterName == "" then return end
            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB then return end

            local encNpcIDs = npcIDsOverride
            if not encNpcIDs or type(encNpcIDs) ~= "table" or #encNpcIDs == 0 then
                if encounterID ~= nil then
                    encNpcIDs = sourceDB.encounters and sourceDB.encounters[encounterID]
                end
            end
            if not encNpcIDs or #encNpcIDs == 0 then return end

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
local WN_CONCENTRATION_MARKER = (ns.L and ns.L["TOOLTIP_CONCENTRATION_MARKER"]) or "Warband Nexus - Concentration"

local function IsConcentrationCurrencyID(currencyID)
    if not currencyID then return false end
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return false end
    local characters = WarbandNexus.db.global.characters
    if not characters then return false end
    for _, charData in pairs(characters) do
        if charData.concentration then
            for _, concData in pairs(charData.concentration) do
                if concData.currencyID == currencyID then
                    return true
                end
            end
        end
    end
    return false
end

local function HasAlreadyInjected(tooltip)
    local numLines = tooltip:NumLines()
    for i = 2, numLines do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        if line then
            local lineText = line:GetText()
            if lineText and not (issecretvalue and issecretvalue(lineText)) and lineText:find("Warband Nexus") then
                return true
            end
        end
    end
    return false
end

local function IsConcentrationTooltip(tooltip)
    local firstLine = _G[tooltip:GetName() .. "TextLeft1"]
    if not firstLine then return false end
    local text = firstLine:GetText()
    if not text or (issecretvalue and issecretvalue(text)) then return false end
    local stripped = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    stripped = stripped:match("^%s*(.-)%s*$")
    if not stripped or stripped == "" then return false end
    if stripped == "Concentration" then return true end
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return false end
    local characters = WarbandNexus.db.global.characters
    if not characters then return false end
    for _, charData in pairs(characters) do
        if charData.concentration then
            for _, concData in pairs(charData.concentration) do
                if concData.currencyID and concData.currencyID > 0 then
                    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, concData.currencyID)
                    if ok and info and info.name then
                        local safeName = info.name
                        if not (issecretvalue and issecretvalue(safeName)) and stripped == safeName then
                            return true
                        end
                    end
                    break
                end
            end
            break
        end
    end
    return false
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
                valueStr = "|cff44ff44" .. entry.max .. " / " .. entry.max .. "|r  |cff44ff44" .. ((ns.L and ns.L["TOOLTIP_FULL"]) or "(Full)") .. "|r"
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
            if not data or not data.id or not IsConcentrationCurrencyID(data.id) then return end
            if HasAlreadyInjected(tooltip) then return end

            if WarbandNexus and WarbandNexus.Debug then
                WarbandNexus:Debug("[Conc Tooltip] Currency PostCall matched, currencyID=" .. tostring(data.id))
            end

            pcall(AppendConcentrationData, tooltip)
        end)
    end

    -- ----------------------------------------------------------------
    -- Layer 2: GameTooltip OnShow fallback
    -- Catches any non-currency code path (custom SetOwner + AddLine).
    -- ----------------------------------------------------------------
    GameTooltip:HookScript("OnShow", function(tooltip)
        if ns.Utilities and not ns.Utilities:IsModuleEnabled("professions") then return end
        if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return end
        if not IsConcentrationTooltip(tooltip) then return end
        if HasAlreadyInjected(tooltip) then return end

        if WarbandNexus and WarbandNexus.Debug then
            WarbandNexus:Debug("[Conc Tooltip] OnShow fallback matched")
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
