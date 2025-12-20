--[[
    Warband Nexus - Tooltip Enhancer Module
    Adds item location information to GameTooltip
    
    Features:
    - Shows Warband Bank quantity and locations
    - Shows Personal Bank quantities per character
    - Click hint to locate item
    - Cached for performance
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Cache for tooltip data (avoid scanning on every hover)
local tooltipCache = {}
local CACHE_DURATION = 10 -- seconds

-- ============================================================================
-- TOOLTIP SCANNING
-- ============================================================================

--[[
    Scan for item locations across all banks
    @param itemID number - Item ID to search for
    @return table - Location data
]]
local function ScanItemLocations(itemID)
    if not itemID or itemID == 0 then
        return nil
    end
    
    -- Check cache first
    local now = time()
    if tooltipCache[itemID] and (now - tooltipCache[itemID].timestamp) < CACHE_DURATION then
        return tooltipCache[itemID].data
    end
    
    local locations = {
        warbandBank = {
            total = 0,
            tabs = {}, -- {tabNum = count}
        },
        personalBanks = {}, -- {charName = {bank = count, bags = count}}
    }
    
    -- Scan Warband Bank
    if WarbandNexus.db.global.warbandBank and WarbandNexus.db.global.warbandBank.items then
        for bagID, bagData in pairs(WarbandNexus.db.global.warbandBank.items) do
            for slotID, item in pairs(bagData) do
                if item.itemID == itemID then
                    local tabNum = bagID - 12 -- Convert bagID to tab number (1-5)
                    locations.warbandBank.total = locations.warbandBank.total + (item.stackCount or 1)
                    locations.warbandBank.tabs[tabNum] = (locations.warbandBank.tabs[tabNum] or 0) + (item.stackCount or 1)
                end
            end
        end
    end
    
    -- Scan Personal Banks (all characters)
    if WarbandNexus.db.global.characters then
        for charKey, charData in pairs(WarbandNexus.db.global.characters) do
            local charName = charData.name or charKey:match("^([^-]+)")
            
            if charData.personalBank then
                for bagID, bagData in pairs(charData.personalBank) do
                    for slotID, item in pairs(bagData) do
                        if item.itemID == itemID then
                            if not locations.personalBanks[charName] then
                                locations.personalBanks[charName] = { bank = 0 }
                            end
                            locations.personalBanks[charName].bank = locations.personalBanks[charName].bank + (item.stackCount or 1)
                        end
                    end
                end
            end
        end
    end
    
    -- Cache result
    tooltipCache[itemID] = {
        data = locations,
        timestamp = now,
    }
    
    return locations
end

--[[
    Clear tooltip cache
    Called when bank data changes
]]
function WarbandNexus:ClearTooltipCache()
    tooltipCache = {}
end

-- ============================================================================
-- TOOLTIP HOOK
-- ============================================================================

--[[
    Add item location info to tooltip
    @param tooltip frame - Tooltip frame
    @param itemLink string - Item link
]]
local function AddItemLocationInfo(tooltip, itemLink)
    if not tooltip or not itemLink then
        return
    end
    
    -- Check if addon is enabled and tooltip enhancement is enabled
    if not WarbandNexus.db or not WarbandNexus.db.profile.enabled then
        return
    end
    
    if not WarbandNexus.db.profile.tooltipEnhancement then
        return
    end
    
    -- Extract item ID from link
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then
        return
    end
    
    -- Scan for locations
    local locations = ScanItemLocations(itemID)
    if not locations then
        return
    end
    
    -- Check if we have any data to show
    local hasWarband = locations.warbandBank.total > 0
    local hasPersonal = false
    for _ in pairs(locations.personalBanks) do
        hasPersonal = true
        break
    end
    
    if not hasWarband and not hasPersonal then
        return -- No locations found
    end
    
    -- Add separator line
    tooltip:AddLine(" ")
    
    -- Warband Bank info
    if hasWarband then
        local tabText = ""
        local tabList = {}
        for tabNum, count in pairs(locations.warbandBank.tabs) do
            table.insert(tabList, string.format("Tab %d", tabNum))
        end
        if #tabList > 0 then
            tabText = " (" .. table.concat(tabList, ", ") .. ")"
        end
        
        tooltip:AddDoubleLine(
            "|cff6a0dad[Warband Bank]|r",
            string.format("|cffffffff%dx|r%s", locations.warbandBank.total, tabText),
            0.7, 0.7, 0.7,
            1, 1, 1
        )
    end
    
    -- Personal Bank info (show top 3 characters)
    if hasPersonal then
        local charList = {}
        for charName, data in pairs(locations.personalBanks) do
            table.insert(charList, {
                name = charName,
                count = data.bank,
            })
        end
        
        -- Sort by count (highest first)
        table.sort(charList, function(a, b) return a.count > b.count end)
        
        -- Show top 3
        local maxChars = 3
        local shown = 0
        for _, charInfo in ipairs(charList) do
            if shown >= maxChars then
                local remaining = #charList - shown
                if remaining > 0 then
                    tooltip:AddDoubleLine(
                        "|cff6a0dad  ...|r",
                        string.format("|cff888888+%d more|r", remaining),
                        0.7, 0.7, 0.7,
                        0.5, 0.5, 0.5
                    )
                end
                break
            end
            
            tooltip:AddDoubleLine(
                string.format("|cff6a0dad  %s|r", charInfo.name),
                string.format("|cffffffff%dx|r", charInfo.count),
                0.7, 0.7, 0.7,
                1, 1, 1
            )
            shown = shown + 1
        end
    end
    
    -- Add hint
    if WarbandNexus.db.profile.tooltipClickHint then
        tooltip:AddLine("|cff00ff00Shift+Click:|r Search in Warband Nexus", 0.5, 0.5, 0.5)
    end
end

--[[
    GameTooltip OnTooltipSetItem hook
]]
local function OnTooltipSetItem(tooltip)
    if not tooltip then return end
    
    -- Safety check: Ensure tooltip has GetItem method (some tooltips don't)
    if not tooltip.GetItem then return end
    
    -- Get item link
    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end
    
    -- Add our info
    AddItemLocationInfo(tooltip, itemLink)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--[[
    Initialize tooltip hooks
    Called during OnEnable
    
    TWW (11.x+): Uses TooltipDataProcessor API
    Legacy (10.x-): Uses OnTooltipSetItem hook
]]
function WarbandNexus:InitializeTooltipEnhancer()
    -- TWW (11.x+): Use new TooltipDataProcessor API
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        -- Register for item tooltips
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            OnTooltipSetItem(tooltip)
        end)
    else
        -- Legacy (pre-11.x): Use OnTooltipSetItem hook
        -- Hook GameTooltip
        if GameTooltip and GameTooltip.HookScript then
            pcall(function()
                GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            end)
        end
        
        -- Hook ItemRefTooltip (for chat links)
        if ItemRefTooltip and ItemRefTooltip.HookScript then
            pcall(function()
                ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            end)
        end
        
        -- Hook shopping tooltips (comparison)
        if ShoppingTooltip1 and ShoppingTooltip1.HookScript then
            pcall(function()
                ShoppingTooltip1:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            end)
        end
        if ShoppingTooltip2 and ShoppingTooltip2.HookScript then
            pcall(function()
                ShoppingTooltip2:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            end)
        end
    end
end

-- ============================================================================
-- SHIFT+CLICK HANDLER (SAFE IMPLEMENTATION)
-- ============================================================================

--[[
    Handle Shift+Click on items to search in addon
    SAFE: Hooks chat frame hyperlinks instead of protected SetItemRef
]]
local function HandleChatHyperlinkEnter(chatFrame, link, text)
    -- Only handle if Shift is down
    if not IsShiftKeyDown() then
        return
    end
    
    -- Only handle item links
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then
        return
    end
    
    -- Safety: Don't do anything in combat
    if InCombatLockdown() then
        return
    end
    
    -- Get item name (async-safe)
    local itemName = C_Item.GetItemNameByID(itemID)
    if not itemName then
        -- Fallback: try GetItemInfo
        itemName = GetItemInfo(itemID)
        if not itemName then
            return
        end
    end
    
    -- Open addon and search for item
    if WarbandNexus.ShowMainWindow then
        WarbandNexus:ShowMainWindow()
    end
    
    -- Switch to Items tab and search
    if WarbandNexus.mainFrame then
        WarbandNexus.mainFrame.currentTab = "items"
        if ns.itemsSearchText ~= nil then
            ns.itemsSearchText = itemName:lower()
        end
        if WarbandNexus.PopulateContent then
            WarbandNexus:PopulateContent()
        end
        
        WarbandNexus:Print(string.format("Searching for: %s", itemName))
    end
end

--[[
    Hook chat frame hyperlink handlers (SAFE approach)
    Called during OnEnable
]]
function WarbandNexus:InitializeTooltipClickHandler()
    -- Hook all chat frames for hyperlink enter events
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame"..i]
        if chatFrame and chatFrame.HookScript then
            pcall(function()
                chatFrame:HookScript("OnHyperlinkEnter", function(self, link, text)
                    if link:match("^item:") then
                        HandleChatHyperlinkEnter(self, link, text)
                    end
                end)
            end)
        end
    end
    
    self:Debug("Tooltip click handler initialized (chat frames)")
end

-- ============================================================================
-- AUTO CACHE INVALIDATION
-- ============================================================================

-- Clear tooltip cache when bank data changes
-- This is called from Core.lua after bank scans
function WarbandNexus:InvalidateTooltipCache()
    tooltipCache = {}
    self:Debug("Tooltip cache invalidated")
end
