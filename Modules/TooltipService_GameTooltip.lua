--[[
    Warband Nexus - GameTooltip hook/injection slice (ops-033)
    TooltipDataProcessor post-calls, collectible drops, concentration, owner placement.
    Loaded before Modules/TooltipService.lua.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
local strsplit = strsplit
local tonumber = tonumber

local GT = ns.TooltipGameTooltip or {}
ns.TooltipGameTooltip = GT

local Utilities = ns.Utilities

local TooltipService

--- Midnight / nameplate aura SetOwner: owner or parent chain may be invalid mid-anchor.
local function IsUsableUIRegion(frame)
    if not frame or type(frame.IsObjectType) ~= "function" then return false end
    local ok, isRegion = pcall(frame.IsObjectType, frame, "Region")
    return ok and isRegion == true
end

function GT.IsWarbandNexusOwner(owner)
    if not IsUsableUIRegion(owner) then return false end
    local isWNFrame = ns.IsWarbandNexusUIFrame
    if type(isWNFrame) == "function" then
        local ok, result = pcall(isWNFrame, owner)
        return ok and result == true
    end
    if type(owner.GetName) ~= "function" then return false end
    local okName, n = pcall(owner.GetName, owner)
    if not okName then return false end
    return n and type(n) == "string" and not (issecretvalue and issecretvalue(n))
        and n:find("WarbandNexus", 1, true) or false
end

function GT.OwnerHasScreenBounds(owner)
    if not IsUsableUIRegion(owner) or type(owner.GetLeft) ~= "function" then return false end
    local ok, l, r, t, b = pcall(function()
        return owner:GetLeft(), owner:GetRight(), owner:GetTop(), owner:GetBottom()
    end)
    if not ok then return false end
    return l ~= nil and r ~= nil and t ~= nil and b ~= nil
end

function GT.AdjustGameTooltipForOwner(tooltip, owner, anchor)
    if not IsUsableUIRegion(tooltip) or not IsUsableUIRegion(owner) then return false end
    if tooltip.GetOwner then
        local okOwner, currentOwner = pcall(tooltip.GetOwner, tooltip)
        if not okOwner or currentOwner ~= owner then return false end
    end
    if not GT.OwnerHasScreenBounds(owner) then return false end
    local sw, sh = GetScreenWidth(), GetScreenHeight()
    TooltipService:ApplyBestTooltipPlacement(tooltip, owner, anchor or "ANCHOR_AUTO", sw, sh)
    return true
end

---Inject collectible drop lines into a GameTooltip.
---Shows header, item hyperlinks, collected/repeatable status, and try counts.
---Shared across NPC (Unit) and Container (Item) tooltip hooks.
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

        -- DB may tag teachable collectibles as generic "item"; align collected with journal/toy APIs
        if drop.type == "item" and not collected and drop.itemID then
            if PlayerHasToy then
                local okToy, hasToy = pcall(PlayerHasToy, drop.itemID)
                if okToy and hasToy == true and not (issecretvalue and issecretvalue(hasToy)) then
                    collected = true
                end
            end
            if not collected and C_MountJournal and C_MountJournal.GetMountFromItem then
                local okMid, mid = pcall(C_MountJournal.GetMountFromItem, drop.itemID)
                if okMid and mid and mid > 0 and not (issecretvalue and issecretvalue(mid)) then
                    local ok2, _, _, _, _, _, _, _, _, _, _, isColl = pcall(C_MountJournal.GetMountInfoByID, mid)
                    if ok2 and isColl == true and not (issecretvalue and issecretvalue(isColl)) then
                        collected = true
                    end
                end
            end
            if not collected and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                local ok1, _, _, _, _, _, _, _, _, _, _, _, specID = pcall(C_PetJournal.GetPetInfoByItemID, drop.itemID)
                if ok1 and specID and specID > 0 and not (issecretvalue and issecretvalue(specID)) then
                    local ok2, numCollected = pcall(C_PetJournal.GetNumCollectedInfo, specID)
                    if ok2 and numCollected and not (issecretvalue and issecretvalue(numCollected)) and numCollected > 0 then
                        collected = true
                    end
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
            if itemLink and type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) then
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
        if isPlanned and not collected then
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
                        local okMid, mountID = pcall(C_MountJournal.GetMountFromItem, yield.itemID)
                        if okMid and mountID and not (issecretvalue and issecretvalue(mountID)) then
                            local okInfo, _, _, _, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountID)
                            if okInfo and not (issecretvalue and isCollected and issecretvalue(isCollected)) then
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
                if yieldPlanned and not yieldCollected then
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

    -- Do not call tooltip:Show() here — retriggers TooltipDataProcessor post-call (refresh/flicker loop).
end

function GT.PreCacheCollectibleItems(service)
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
            service:Debug("Pre-cached " .. #itemIDs .. " collectible item IDs for tooltip readiness")
        end
    end

    ProcessBatch()
end

local function SafeTooltipNumber(val)
    if val == nil then return nil end
    if issecretvalue and issecretvalue(val) then return nil end
    return tonumber(val)
end

--- widgetSetID is stored on GameTooltip.widgetContainer (Blizzard_GameTooltip), not the tooltip root.
local function ResolveTooltipWidgetSetID(tooltip)
    if not tooltip then return nil end
    local widgetSetID = tooltip.widgetSetID
    if widgetSetID == nil then
        local widgetContainer = tooltip.widgetContainer
        if widgetContainer then
            widgetSetID = widgetContainer.widgetSetID
        end
    end
    return widgetSetID
end

--- Blizzard UI widget tooltips (map vignettes, quest pins, etc.).
--- Never AddLine or store custom fields on these tooltips — widget layout uses secret numbers.
local function IsBlizzardWidgetTooltip(tooltip)
    if not tooltip then return false end
    local widgetSetID = ResolveTooltipWidgetSetID(tooltip)
    if widgetSetID ~= nil then
        if issecretvalue and issecretvalue(widgetSetID) then return true end
        if widgetSetID ~= 0 then return true end
    end
    local widgetContainer = tooltip.widgetContainer
    if widgetContainer then
        local shown = widgetContainer.shownWidgetCount
        if type(shown) == "number" and shown > 0
            and not (issecretvalue and issecretvalue(shown)) then
            return true
        end
    end
    return false
end

--- Injection state in weak tables — never assign tooltip._wn* (taints GameTooltip).
local tooltipInjectTokensByFrame = setmetatable({}, { __mode = "k" })
local tooltipItemCountTimerByFrame = setmetatable({}, { __mode = "k" })

--- Tooltip types that may mount UI widget sets during Show (after post-call).
local function WillTooltipUseWidgets(tooltip, data)
    if IsBlizzardWidgetTooltip(tooltip) then return true end
    if not data then return false end
    local ws = data.widgetSetID
    if ws ~= nil then
        if issecretvalue and issecretvalue(ws) then return true end
        if ws ~= 0 then return true end
    end
    local tooltipType = data.type
    if tooltipType == nil then return false end
    if issecretvalue and issecretvalue(tooltipType) then return true end
    local T = Enum and Enum.TooltipDataType
    if not T then return false end
    return tooltipType == T.MinimapMouseover
        or tooltipType == T.Quest
        or tooltipType == T.Object
end

--- Resize NineSlice after lines added post-Show (deferred widget-check path only).
local function RefreshGameTooltipLayout(tooltip)
    if not tooltip or not tooltip.Show then return end
    if tooltip.IsShown and not tooltip:IsShown() then return end
    -- Injection tokens prevent duplicate AddLine if Show retriggers post-call.
    tooltip:Show()
end

--- TooltipDataProcessor post-call runs before InternalProcessInfo :Show().
--- Bag/item lines must inject synchronously so backdrop sizing includes WN Search.
--- Widget map/quest tooltips defer one frame so IsBlizzardWidgetTooltip can skip AddLine.
local function RunGameTooltipInjection(tooltip, data, fn)
    if not tooltip or type(fn) ~= "function" then return end
    if IsBlizzardWidgetTooltip(tooltip) then return end

    local function inject(deferred)
        if tooltip.IsShown and not tooltip:IsShown() then return end
        if IsBlizzardWidgetTooltip(tooltip) then return end
        pcall(fn)
        if deferred then
            RefreshGameTooltipLayout(tooltip)
        end
    end

    if WillTooltipUseWidgets(tooltip, data) and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not tooltip then return end
            inject(true)
        end)
    else
        inject(false)
    end
end

local function ParseItemIDFromItemLink(link)
    if not link or type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then
        return nil
    end
    local idStr = link:match("item:(%d+)")
    return idStr and tonumber(idStr) or nil
end

--- Resolve item id for WN Search counts (Struct TooltipData.id + hyperlink; Midnight-safe).
local function ResolveItemTooltipID(data)
    if not data then return nil end
    local id = SafeTooltipNumber(data.id)
    if id then return id end
    return ParseItemIDFromItemLink(data.hyperlink)
end

--- Per-tooltip injection guard (prevents post-call + Show() refresh loops).
local function TooltipInjectionAlreadyDone(tooltip, token)
    if not tooltip or not token then return false end
    local tokens = tooltipInjectTokensByFrame[tooltip]
    return tokens and tokens[token] == true
end

local function MarkTooltipInjectionDone(tooltip, token)
    if not tooltip or not token then return end
    local tokens = tooltipInjectTokensByFrame[tooltip]
    if not tokens then
        tokens = {}
        tooltipInjectTokensByFrame[tooltip] = tokens
    end
    tokens[token] = true
end

local function ClearTooltipInjectionTokens(tooltip)
    if not tooltip then return end
    tooltipInjectTokensByFrame[tooltip] = nil
    local timer = tooltipItemCountTimerByFrame[tooltip]
    if timer then
        if timer.Cancel then
            timer:Cancel()
        end
        tooltipItemCountTimerByFrame[tooltip] = nil
    end
end

local function InstallGameTooltipInjectionClearHooks()
    if TooltipService._injectionHideHooked then return end
    if not hooksecurefunc then return end
    TooltipService._injectionHideHooked = true
    -- hooksecurefunc(Hide) clears weak-table injection state only (never tooltip._wn* fields).
    local function hookHide(frame)
        if not frame then return end
        hooksecurefunc(frame, "Hide", function(service)
            ClearTooltipInjectionTokens(service)
        end)
    end
    if GameTooltip then hookHide(GameTooltip) end
    if ItemRefTooltip then hookHide(ItemRefTooltip) end
end

local function AppendWNItemCountLines(tooltip, itemID)
    if not tooltip or not itemID or not tooltip.AddLine or not tooltip.AddDoubleLine then
        return false
    end
    if not WarbandNexus or not WarbandNexus.GetDetailedItemCountsFast then
        return false
    end

    local details = WarbandNexus:GetDetailedItemCountsFast(itemID)
    if not details then return false end

    local total = details.warbandBank or 0
    for i = 1, #details.characters do
        total = total + details.characters[i].bagCount + details.characters[i].bankCount
    end
    if total == 0 then return false end

    tooltip:AddLine(" ")
    tooltip:AddLine((ns.L and ns.L["WN_SEARCH"]) or "WN Search", 0.4, 0.8, 1, 1)

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
    return true
end

--- Mythic keystones share one item template ID; bag/bank counts by itemID are misleading.
--- Show per-character owned keys from PvE cache instead (same source as /wn keys).
local function AppendWNKeystoneLines(tooltip, hyperlink)
    if not tooltip or not tooltip.AddLine or not tooltip.AddDoubleLine then
        return false
    end
    if not WarbandNexus or not WarbandNexus.GetAllCharacters then
        return false
    end

    local parsed = Utilities and Utilities.ParseKeystoneHyperlink and Utilities:ParseKeystoneHyperlink(hyperlink)
    if parsed and parsed.level and parsed.level > 0 then
        local thisName = Utilities and Utilities.ResolveKeystoneDungeonName
            and Utilities:ResolveKeystoneDungeonName(parsed)
            or "Unknown Dungeon"
        tooltip:AddLine(" ")
        local thisFmt = (ns.L and ns.L["TOOLTIP_KEYSTONE_THIS"]) or "This key: +%d %s"
        tooltip:AddLine(string.format(thisFmt, parsed.level, thisName), 1, 0.82, 0, 1)
    end

    local characters = WarbandNexus:GetAllCharacters()
    if not characters or #characters == 0 then return parsed ~= nil end

    local roster = {}
    local seenCanon = {}
    for i = 1, #characters do
        local char = characters[i]
        local charKey = char._key
        local canon = (Utilities and Utilities.GetCanonicalCharacterKey and Utilities:GetCanonicalCharacterKey(charKey))
            or charKey
        if canon and not seenCanon[canon] then
            seenCanon[canon] = true
            local keystone = nil
            if WarbandNexus.GetPvEData then
                local pve = WarbandNexus:GetPvEData(charKey)
                keystone = pve and pve.keystone
            end
            if (not keystone or not keystone.level or keystone.level <= 0) and char.mythicKey then
                keystone = char.mythicKey
            end
            if keystone and keystone.level and keystone.level > 0 then
                local dungeonName = Utilities and Utilities.ResolveKeystoneDungeonName
                    and Utilities:ResolveKeystoneDungeonName(keystone)
                    or (keystone.dungeonName or keystone.name or "Unknown Dungeon")
                roster[#roster + 1] = {
                    name = char.name or "?",
                    classFile = char.classFile or char.class,
                    level = keystone.level,
                    dungeon = dungeonName,
                }
            end
        end
    end

    if #roster == 0 then return parsed ~= nil end

    table.sort(roster, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return (a.name or "") < (b.name or "")
    end)

    tooltip:AddLine(" ")
    tooltip:AddLine((ns.L and ns.L["TOOLTIP_WN_KEYS"]) or "WN Keys", 0.4, 0.8, 1, 1)

    local isShift = IsShiftKeyDown()
    local maxShow = isShift and 999 or 8
    local shown = 0
    for i = 1, #roster do
        if shown >= maxShow then break end
        local row = roster[i]
        local cc = RAID_CLASS_COLORS[row.classFile] or { r = 1, g = 1, b = 1 }
        local keyFmt = (ns.L and ns.L["EA_TOOLTIP_KEYSTONE_FORMAT"]) or "+%d %s"
        tooltip:AddDoubleLine(
            row.name,
            string.format(keyFmt, row.level, row.dungeon),
            cc.r, cc.g, cc.b,
            1, 0.82, 0
        )
        shown = shown + 1
    end
    if not isShift and #roster > maxShow then
        tooltip:AddLine((ns.L and ns.L["TOOLTIP_HOLD_SHIFT"]) or "  Hold [Shift] for full list", 0.5, 0.5, 0.5)
    end
    return true
end

function GT.InitializeGameTooltipHook(service)
    -- Modern TWW API (taint-safe)
    if not TooltipDataProcessor then
        service:Debug("TooltipDataProcessor not available - tooltip injection disabled")
        return
    end

    InstallGameTooltipInjectionClearHooks()

    -- ITEM TOOLTIP — single post-call (counts + planned + container drops)
    -- One TooltipDataProcessor registration avoids triple invocation per hover.
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        RunGameTooltipInjection(tooltip, data, function()
        if IsBlizzardWidgetTooltip(tooltip) then return end
        local itemID = ResolveItemTooltipID(data)
        local dataInstanceID = data and data.dataInstanceID

        -- WN Search counts per character (sync pre-Show; never call Show() here — retriggers rebuild loop)
        if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile then
            local showTooltipItemCount = WarbandNexus.db.profile.showTooltipItemCount
            if showTooltipItemCount == nil then
                showTooltipItemCount = WarbandNexus.db.profile.showItemCount
            end
            if showTooltipItemCount and tooltip and itemID then
                local isKeystone = Utilities and Utilities.IsKeystoneItemID and Utilities:IsKeystoneItemID(itemID)
                local countToken = (isKeystone and "keystone:" or "counts:")
                    .. tostring(dataInstanceID or 0) .. ":" .. tostring(itemID)
                if not TooltipInjectionAlreadyDone(tooltip, countToken) then
                    local ok, err = pcall(function()
                        local injected
                        if isKeystone then
                            injected = AppendWNKeystoneLines(tooltip, data and data.hyperlink)
                        else
                            injected = AppendWNItemCountLines(tooltip, itemID)
                        end
                        if injected then
                            MarkTooltipInjectionDone(tooltip, countToken)
                        end
                    end)
                    if not ok and WarbandNexus.Debug then
                        WarbandNexus:Debug("[Tooltip] Item count inject error for itemID " .. tostring(itemID) .. ": " .. tostring(err))
                    end
                end
            end
        end

        -- "(Planned)" indicator
        if WarbandNexus and tooltip and tooltip.AddLine and itemID then
            local function ItemTooltipCollectibleOwned(id)
                if not id then return false end
                if PlayerHasToy then
                    local okToy, hasToy = pcall(PlayerHasToy, id)
                    if okToy and hasToy == true and not (issecretvalue and issecretvalue(hasToy)) then
                        return true
                    end
                end
                if C_MountJournal and C_MountJournal.GetMountFromItem then
                    local ok1, mountID = pcall(C_MountJournal.GetMountFromItem, id)
                    if ok1 and mountID and mountID > 0 and not (issecretvalue and issecretvalue(mountID)) then
                        local ok2, _, _, _, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountID)
                        if ok2 and isCollected == true and not (issecretvalue and issecretvalue(isCollected)) then
                            return true
                        end
                    end
                end
                if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                    local ok1, _, _, _, _, _, _, _, _, _, _, _, specID = pcall(C_PetJournal.GetPetInfoByItemID, id)
                    if ok1 and specID and specID > 0 and not (issecretvalue and issecretvalue(specID)) then
                        local ok2, numCollected = pcall(C_PetJournal.GetNumCollectedInfo, specID)
                        if ok2 and numCollected and not (issecretvalue and issecretvalue(numCollected)) and numCollected > 0 then
                            return true
                        end
                    end
                end
                return false
            end

            local planned = false
            if WarbandNexus.IsItemPlanned then
                planned = WarbandNexus:IsItemPlanned(nil, itemID)
            end
            if not planned and WarbandNexus.IsMountPlanned
                and C_MountJournal and C_MountJournal.GetMountFromItem then
                local mountID = C_MountJournal.GetMountFromItem(itemID)
                if mountID and mountID > 0 and not (issecretvalue and issecretvalue(mountID)) then
                    planned = WarbandNexus:IsMountPlanned(mountID)
                end
            end
            if not planned and WarbandNexus.IsPetPlanned
                and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                local _, _, _, _, _, _, _, _, _, _, _, _, specID = C_PetJournal.GetPetInfoByItemID(itemID)
                if specID and specID > 0 and not (issecretvalue and issecretvalue(specID)) then
                    planned = WarbandNexus:IsPetPlanned(specID)
                end
            end

            if planned and not ItemTooltipCollectibleOwned(itemID) then
                local plannedToken = "planned:" .. tostring(dataInstanceID or 0) .. ":" .. tostring(itemID)
                if not TooltipInjectionAlreadyDone(tooltip, plannedToken) then
                    local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
                    tooltip:AddLine("|cffffcc00(" .. plannedWord .. ")|r")
                    MarkTooltipInjectionDone(tooltip, plannedToken)
                end
            end
        end

        -- Container collectible drops (paragon caches, etc.)
        if itemID and (tooltip == GameTooltip or tooltip == ItemRefTooltip) then
            local sourceDB = ns.CollectibleSourceDB
            if sourceDB and sourceDB.containers then
                local containerData = sourceDB.containers[itemID]
                if containerData then
                    local drops = containerData.drops or containerData
                    if drops and type(drops) == "table" and #drops > 0 then
                        local dropsToken = "drops:" .. tostring(dataInstanceID or 0) .. ":" .. tostring(itemID)
                        if not TooltipInjectionAlreadyDone(tooltip, dropsToken) then
                            InjectCollectibleDropLines(tooltip, drops)
                            MarkTooltipInjectionDone(tooltip, dropsToken)
                        end
                    end
                end
            end
        end
        end)
    end)

    service:Debug("Item tooltip hook initialized (counts + planned + container drops)")
    
    -- UNIT TOOLTIP: Collectible drop info from CollectibleSourceDB
    -- Shows item hyperlinks + collection status + try count on NPCs
    if Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        -- Upvalue WoW APIs used in the hook
        local UnitGUID = UnitGUID
        local strsplit = strsplit
        local tonumber = tonumber

        -- GameObject IDs that WoW sometimes shows with Unit (Creature) tooltip. Do not inject
        -- collectible drops on these (they are objects, not NPCs that drop mounts/pets).
        local UNIT_TOOLTIP_OBJECT_IDS = {
            [209780] = true,  -- Abandoned Restoration Stone (Midnight delve / world object as Unit tooltip)
            [209781] = true,  -- Empowered Restoration Stone (Midnight)
        }
        -- Unit names that are known GameObjects (name-fallback path). Do not show drops.
        local UNIT_TOOLTIP_OBJECT_NAMES = {
            ["Abandoned Restoration Stone"] = true,
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
            local addon = WarbandNexus or _G[ADDON_NAME]
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
            local addon = WarbandNexus or _G[ADDON_NAME]
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
            RunGameTooltipInjection(tooltip, data, function()
            if IsBlizzardWidgetTooltip(tooltip) then return end

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
                local mapID = SafeTooltipNumber(rawMapID)
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
                    mapID = SafeTooltipNumber(mapInfo and mapInfo.parentMapID)
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
                if ok and canAttack and not (issecretvalue and issecretvalue(canAttack)) and canAttack == true then
                    return true
                end
                -- Dead units are no longer attackable; check if it's a lootable corpse
                local okDead, isDead = pcall(UnitIsDead, "mouseover")
                if okDead and isDead and not (issecretvalue and issecretvalue(isDead)) and isDead == true then
                    local okReact, reaction = pcall(UnitReaction, "mouseover", "player")
                    if okReact and reaction and not (issecretvalue and issecretvalue(reaction))
                        and type(reaction) == "number" and reaction <= 4 then
                        return true
                    end
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

            -- Per-NPC collectible drops: only on hostile/attackable units. Friendly delve objects and
            -- NPCs that use a Creature unit tooltip must not show unrelated mount/pet lines from DB.
            if drops and #drops > 0 and not IsMouseoverAttackable() then
                drops = nil
            end
            if (not drops or #drops == 0) and (not zoneDrops or #zoneDrops == 0) then return end

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
        end)

        -- Expose diagnostic accessors (MUST be inside this scope to access closures)
        service._getLocalizedNpcNameIndex = GetLocalizedNpcNameIndex
        service._isNpcIndexReady = function() return npcIndexBuildComplete end
        -- Force rebuild: resets to English fallback and reloads cache
        service._forceRebuildIndex = function()
            localizedNpcNameIndex = {}
            npcIndexBuildComplete = false
            InitializeEnglishFallback()
            TryLoadFromCache()
            npcIndexBuildComplete = true
            return localizedNpcNameIndex
        end

        -- ENCOUNTER_END feed: Injects localized encounter name into tooltip caches.
        -- Called from TryCounterService when a boss is killed in an instance.
        -- Midnight 12.0+: treat encounterName / encounterID as potentially secret — no ==, no table keys
        -- until cleared (WN-SECURITY-taint). npcIDsOverride allows ID-secret kills to still cache by name
        -- when the name is non-secret.
        service._feedEncounterKill = function(encounterName, encounterID, npcIDsOverride)
            if not encounterName or (issecretvalue and issecretvalue(encounterName)) then return end
            if type(encounterName) ~= "string" or encounterName == "" then return end
            local sourceDB = ns.CollectibleSourceDB
            if not sourceDB then return end

            local encNpcIDs = npcIDsOverride
            if not encNpcIDs or type(encNpcIDs) ~= "table" or #encNpcIDs == 0 then
                if encounterID ~= nil and not (issecretvalue and issecretvalue(encounterID)) then
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

        service:Debug("Unit tooltip hook initialized (collectible drops)")
    end

    service:Debug("GameTooltip hook initialized (TooltipDataProcessor)")
end

---Run self-diagnostic on tooltip systems. Called by /wn validate tooltip.
---Verifies localized npcNameIndex, lockout quest integration, and EJ API availability.
function GT.RunDiagnostics(service)
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
    if service._forceRebuildIndex then
        index = service._forceRebuildIndex()
    elseif service._getLocalizedNpcNameIndex then
        index = service._getLocalizedNpcNameIndex()
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
    addCheck("ENCOUNTER_END feed", service._feedEncounterKill ~= nil,
        service._feedEncounterKill and "Active — boss kills inject localized names into cache"
            or "NOT active — tooltip hook may not be initialized")

    return results
end

local concentrationHookInstalled = false
local WN_CONCENTRATION_MARKER = (ns.L and ns.L["TOOLTIP_CONCENTRATION_MARKER"]) or "Warband Nexus - Concentration"
local CONCENTRATION_CACHE_TTL = 10
local concentrationCurrencyCache = {
    builtAt = 0,
    idSet = {},
    nameSet = {},
}

local function GetConcentrationCurrencyCache()
    local now = GetTime and GetTime() or 0
    if concentrationCurrencyCache.builtAt > 0 and (now - concentrationCurrencyCache.builtAt) < CONCENTRATION_CACHE_TTL then
        return concentrationCurrencyCache
    end

    local idSet = {}
    local nameSet = {}
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters then
        for _, charData in pairs(WarbandNexus.db.global.characters) do
            local concentrationData = charData and charData.concentration
            if concentrationData then
                for _, concData in pairs(concentrationData) do
                    local currencyID = concData and concData.currencyID
                    if type(currencyID) == "number" and currencyID > 0 then
                        idSet[currencyID] = true
                    end
                end
            end
        end
    end

    for currencyID in pairs(idSet) do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        if ok and info and info.name and not (issecretvalue and issecretvalue(info.name)) then
            nameSet[info.name] = true
        end
    end

    concentrationCurrencyCache.builtAt = now
    concentrationCurrencyCache.idSet = idSet
    concentrationCurrencyCache.nameSet = nameSet
    return concentrationCurrencyCache
end

local function IsConcentrationCurrencyID(currencyID)
    if not currencyID then return false end
    local cache = GetConcentrationCurrencyCache()
    return cache.idSet[currencyID] == true
end

local function HasAlreadyInjected(tooltip)
    local marker = (ns.L and ns.L["TOOLTIP_CONCENTRATION_MARKER"]) or "Warband Nexus - Concentration"
    local numLines = tooltip:NumLines()
    for i = 2, numLines do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        if line then
            local lineText = line:GetText()
            if lineText and not (issecretvalue and issecretvalue(lineText)) and marker ~= "" and lineText:find(marker, 1, true) then
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
    local cache = GetConcentrationCurrencyCache()
    if cache.nameSet[stripped] then return true end
    return stripped == "Concentration"
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
                valueStr = (ns.UI_GetBrightHex and ns.UI_GetBrightHex() or "|cffeeeeee") .. "~" .. estimated .. " / " .. entry.max .. "|r  "
                    .. (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted") or "|cff888888") .. "(" .. timeStr .. ")|r"
            end

            tooltip:AddDoubleLine(
                "    " .. charColor .. entry.charName .. "|r",
                valueStr,
                1, 1, 1, 1, 1, 1
            )
        end
    end

    -- Do not call tooltip:Show() — retriggers widget layout and taints GameTooltip (Midnight).
end

function GT.InstallConcentrationTooltipHook(service)
    if concentrationHookInstalled then return end

    -- Layer 1: TooltipDataProcessor for Currency tooltips (modern API)
    -- Concentration is a currency. When Blizzard calls
    -- GameTooltip:SetCurrencyByID(concentrationCurrencyID), this fires.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum.TooltipDataType and Enum.TooltipDataType.Currency then
        local CURRENCY_TYPE = Enum.TooltipDataType.Currency
        TooltipDataProcessor.AddTooltipPostCall(CURRENCY_TYPE, function(tooltip, data)
            if tooltip ~= GameTooltip then return end
            if ns.Utilities and not ns.Utilities:IsModuleEnabled("professions") then return end
            if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return end
            if not data or not data.id or not IsConcentrationCurrencyID(data.id) then return end
            RunGameTooltipInjection(tooltip, data, function()
                if IsBlizzardWidgetTooltip(tooltip) then return end
                if HasAlreadyInjected(tooltip) then return end

                if WarbandNexus and WarbandNexus.Debug then
                    WarbandNexus:Debug("[Conc Tooltip] Currency PostCall matched, currencyID=" .. tostring(data.id))
                end

                pcall(AppendConcentrationData, tooltip)
            end)
        end)
    end

    -- Layer 2: hooksecurefunc(Show) fallback — taint-safe (no HookScript on GameTooltip).
    if hooksecurefunc and GameTooltip then
        hooksecurefunc(GameTooltip, "Show", function(tooltip)
            if IsBlizzardWidgetTooltip(tooltip) then return end
            if ns.Utilities and not ns.Utilities:IsModuleEnabled("professions") then return end
            if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return end
            if not IsConcentrationTooltip(tooltip) then return end
            if HasAlreadyInjected(tooltip) then return end

            if WarbandNexus and WarbandNexus.Debug then
                WarbandNexus:Debug("[Conc Tooltip] Show fallback matched")
            end

            pcall(AppendConcentrationData, tooltip)
        end)
    end

    concentrationHookInstalled = true
    if service.Debug then
        service:Debug("Concentration tooltip hook installed (TooltipDataProcessor + Show hooksecurefunc)")
    end
end

-- Install the hook immediately at load time — GameTooltip is always available.


function GT.InstallGameTooltipOwnerHook(service, SafeDefer)
    TooltipService = service
    if not service._gameTooltipOwnerHooked and hooksecurefunc and GameTooltip then
        service._gameTooltipOwnerHooked = true
        hooksecurefunc(GameTooltip, "SetOwner", function(tooltip, owner, anchor)
            if tooltip ~= GameTooltip then return end
            if not owner then return end
            if anchor == "ANCHOR_CURSOR" then return end
            local okCheck, isWN = pcall(GT.IsWarbandNexusOwner, owner)
            if not okCheck or not isWN then return end
            local anch = anchor or "ANCHOR_AUTO"
            local okAdjust, adjusted = pcall(GT.AdjustGameTooltipForOwner, tooltip, owner, anch)
            if okAdjust and adjusted then return end
            SafeDefer(function()
                pcall(GT.AdjustGameTooltipForOwner, GameTooltip, owner, anch)
            end)
        end)
    end
end

function GT.Install(service)
    TooltipService = service
    GT.IsBlizzardWidgetTooltip = IsBlizzardWidgetTooltip
    service.PreCacheCollectibleItems = function(s, ...) return GT.PreCacheCollectibleItems(s, ...) end
    service.InitializeGameTooltipHook = function(s, ...) return GT.InitializeGameTooltipHook(s, ...) end
    service.RunDiagnostics = function(s, ...) return GT.RunDiagnostics(s, ...) end
    service.InstallConcentrationTooltipHook = function(s, ...) return GT.InstallConcentrationTooltipHook(s, ...) end
    GT.InstallConcentrationTooltipHook(service)
end

