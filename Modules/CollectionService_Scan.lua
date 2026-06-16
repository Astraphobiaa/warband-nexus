--[[
    Warband Nexus - Collection bag-scan / loot detection (ops-031 slice)
    BAG_UPDATE_DELAYED + CHAT_MSG_LOOT host; emits WN_COLLECTIBLE_OBTAINED after dedup.
    Loaded after CollectionService_NotifyDedup.lua, before CollectionService.lua.
    WN_NONUI_UI: bagScanFrame is a background event host only.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local Notify = ns.CollectionNotify
local issecretvalue = issecretvalue
local Constants = ns.Constants
local E = Constants.EVENTS

local IsDebugVerboseEnabled = ns.IsDebugVerboseEnabled
local DebugPrint = (ns.CreateDebugPrinter and ns.CreateDebugPrinter(
    nil,
    { verboseOnly = true, suppressWhenTryCounterLoot = true }
)) or function() end
local function DebugPrintf(fmt, ...)
    if IsDebugVerboseEnabled and IsDebugVerboseEnabled() then
        DebugPrint(string.format(fmt, ...))
    end
end

local Scan = ns.CollectionScan or {}
ns.CollectionScan = Scan
local debugprofilestop = debugprofilestop

Scan.previousBagContents = Scan.previousBagContents or {}
Scan.isInitialized = Scan.isInitialized or false
Scan.pendingRetryItems = Scan.pendingRetryItems or {}
Scan.lastCollectibleScanTime = Scan.lastCollectibleScanTime or 0

local COLLECTIBLE_SCAN_THROTTLE = 0.08

local function IsCollectionsModuleEnabled()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    return db and db.modulesEnabled and db.modulesEnabled.collections ~= false
end

local function ScanBagsForNewCollectibles(specificBagIDs)
    local previousBagContents = Scan.previousBagContents
    local pendingRetryItems = Scan.pendingRetryItems
    local currentBagContents = {}
    local newCollectibles = {}
    local itemsCacheSnaps = ns.ItemsCacheBagSnapshots
    local snapNow = GetTime()

    local function FillBagSlotsFromItemsCache(bagID)
        local snap = itemsCacheSnaps and itemsCacheSnaps[bagID]
        if not snap or not snap.slots or (snapNow - (snap.at or 0)) > 0.65 then
            return false
        end
        for slotKey, itemID in pairs(snap.slots) do
            currentBagContents[slotKey] = itemID
        end
        return true
    end

    local function ScanBagSlotsLive(bagID)
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        if not numSlots then return end
        for slotID = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
            if itemInfo and itemInfo.itemID then
                local itemID = itemInfo.itemID
                local slotKey = bagID .. "_" .. slotID
                currentBagContents[slotKey] = itemID
                if not previousBagContents[slotKey] or previousBagContents[slotKey] ~= itemID then
                    local _, _, _, _, _, preClassID = GetItemInfoInstant(itemID)
                    if preClassID and preClassID ~= 0 and preClassID ~= 15 and preClassID ~= 17 then
                        -- not a collectible
                    elseif not preClassID then
                        if not pendingRetryItems[slotKey] then
                            pendingRetryItems[slotKey] = {
                                itemID = itemID,
                                hyperlink = itemInfo.hyperlink,
                                retries = 0
                            }
                        end
                    else
                        local collectibleInfo = WarbandNexus:CheckNewCollectible(itemID, itemInfo.hyperlink)
                        if collectibleInfo then
                            local repStr = "n/a"
                            if WarbandNexus.IsRepeatableCollectible then
                                repStr = tostring(WarbandNexus:IsRepeatableCollectible(collectibleInfo.type, collectibleInfo.id))
                            end
                            DebugPrintf(
                                "|cff00ff00[WN BAG SCAN]|r slot=%s Source=Bag IsInCollectible=True Repeatable=%s WhatIs=%s id=%s name=%s",
                                slotKey, repStr, collectibleInfo.type, tostring(collectibleInfo.id), collectibleInfo.name or "?")

                            table.insert(newCollectibles, {
                                type = collectibleInfo.type,
                                itemID = itemID,
                                collectibleID = collectibleInfo.id,
                                itemLink = itemInfo.hyperlink,
                                itemName = collectibleInfo.name,
                                icon = collectibleInfo.icon
                            })
                        end
                    end
                end
            end
        end
    end

    local function DiffBagSlotsFromItemsCache(bagID)
        local snap = itemsCacheSnaps and itemsCacheSnaps[bagID]
        if not snap or not snap.slots or (snapNow - (snap.at or 0)) > 0.65 then
            return false
        end
        for slotKey, itemID in pairs(snap.slots) do
            if not previousBagContents[slotKey] or previousBagContents[slotKey] ~= itemID then
                local _, _, _, _, _, preClassID = GetItemInfoInstant(itemID)
                if preClassID and preClassID ~= 0 and preClassID ~= 15 and preClassID ~= 17 then
                    -- not a collectible
                elseif not preClassID then
                    if not pendingRetryItems[slotKey] then
                        pendingRetryItems[slotKey] = {
                            itemID = itemID,
                            hyperlink = nil,
                            retries = 0
                        }
                    end
                else
                    local collectibleInfo = WarbandNexus:CheckNewCollectible(itemID, nil)
                    if collectibleInfo then
                        table.insert(newCollectibles, {
                            type = collectibleInfo.type,
                            itemID = itemID,
                            collectibleID = collectibleInfo.id,
                            itemLink = nil,
                            itemName = collectibleInfo.name,
                            icon = collectibleInfo.icon
                        })
                    end
                end
            end
        end
        return true
    end

    if not Scan.isInitialized then
        for bagID = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots then
                for slotID = 1, numSlots do
                    local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                    if itemInfo and itemInfo.itemID then
                        local slotKey = bagID .. "_" .. slotID
                        currentBagContents[slotKey] = itemInfo.itemID
                    end
                end
            end
        end

        Scan.previousBagContents = currentBagContents
        Scan.isInitialized = true

        local itemCount = 0
        for _ in pairs(currentBagContents) do itemCount = itemCount + 1 end

        DebugPrint("|cff9370DB[WN CollectionService]|r Bag scan initialized (tracking " .. itemCount .. " items, no notifications)")
        return nil
    end

    local scanAll = (specificBagIDs == nil)

    for slotKey, pending in pairs(pendingRetryItems) do
        local collectibleInfo = WarbandNexus:CheckNewCollectible(pending.itemID, pending.hyperlink)
        if collectibleInfo then
            local repStr = "n/a"
            if WarbandNexus.IsRepeatableCollectible then
                repStr = tostring(WarbandNexus:IsRepeatableCollectible(collectibleInfo.type, collectibleInfo.id))
            end
            DebugPrintf(
                "|cff00ff00[WN BAG SCAN]|r RETRY Source=Bag IsInCollectible=True Repeatable=%s WhatIs=%s id=%s name=%s",
                repStr, collectibleInfo.type, tostring(collectibleInfo.id), collectibleInfo.name or "?")
            table.insert(newCollectibles, {
                type = collectibleInfo.type,
                itemID = pending.itemID,
                collectibleID = collectibleInfo.id,
                itemLink = pending.hyperlink,
                itemName = collectibleInfo.name,
                icon = collectibleInfo.icon
            })
            pendingRetryItems[slotKey] = nil
        else
            pending.retries = (pending.retries or 0) + 1
            if pending.retries >= 5 then
                pendingRetryItems[slotKey] = nil
            end
        end
    end

    for bagID = 0, 4 do
        if scanAll or specificBagIDs[bagID] then
            if FillBagSlotsFromItemsCache(bagID) then
                DiffBagSlotsFromItemsCache(bagID)
            else
                ScanBagSlotsLive(bagID)
            end
        end
    end

    if not scanAll then
        for slotKey, itemID in pairs(previousBagContents) do
            local bagNum = tonumber(slotKey:match("^(%d+)"))
            if bagNum and not specificBagIDs[bagNum] then
                currentBagContents[slotKey] = itemID
            end
        end
    end

    Scan.previousBagContents = currentBagContents

    local itemCount = 0
    for _ in pairs(currentBagContents) do itemCount = itemCount + 1 end
    local pendingCount = 0
    for _ in pairs(pendingRetryItems) do pendingCount = pendingCount + 1 end
    DebugPrintf(
        "|cff00ccff[WN BAG SCAN]|r Source=Bag ScanComplete newCollectibles=%d trackedItemSlots=%d pendingRetry=%d",
        #newCollectibles, itemCount, pendingCount)

    if pendingCount > 0 then
        C_Timer.After(0.4, function()
            if WarbandNexus.OnBagUpdateForCollectibles then
                WarbandNexus:OnBagUpdateForCollectibles()
            end
        end)
    end

    return #newCollectibles > 0 and newCollectibles or nil
end

---Measure-only bag collectible diff scan (no toasts / WN_COLLECTIBLE_OBTAINED). Used by /wn bagdebug stress.
function Scan.MeasureBagsForCollectibles(specificBagIDs)
    local t0 = debugprofilestop()
    ScanBagsForNewCollectibles(specificBagIDs)
    return debugprofilestop() - t0
end

function WarbandNexus:OnBagUpdateForCollectibles(specificBagIDs)
    if not IsCollectionsModuleEnabled() then return end
    local now = GetTime()
    if (now - Scan.lastCollectibleScanTime) < COLLECTIBLE_SCAN_THROTTLE then
        return
    end
    Scan.lastCollectibleScanTime = now

    local newCollectibles = ScanBagsForNewCollectibles(specificBagIDs)

    if newCollectibles then
        for i = 1, #newCollectibles do
            local collectible = newCollectibles[i]
            local suppressForTryCounter = (collectible.type == "mount" or collectible.type == "pet" or collectible.type == "toy")
                and WarbandNexus.ShouldSuppressBagCollectibleToastAsTryCounterDuplicate
                and WarbandNexus:ShouldSuppressBagCollectibleToastAsTryCounterDuplicate(
                    collectible.type, collectible.collectibleID, collectible.itemID)

            if suppressForTryCounter then
                Notify.MarkAsDetectedInBag(collectible.type, collectible.collectibleID)
                Notify.MarkAsNotified(collectible.type, collectible.collectibleID)
                Notify.MarkAsShownByName(collectible.itemName)
                if collectible.type == "pet" and collectible.itemID == collectible.collectibleID then
                    Notify.MarkPetNameBagCooldown(collectible.itemName)
                end
                Notify.MarkAsPermanentlyNotified(collectible.type, collectible.collectibleID)
            elseif Notify.WasAlreadyNotified(collectible.type, collectible.collectibleID) then
                DebugPrint("|cff888888[WN CollectionService]|r PERMANENT DEDUP (bag scan): " .. collectible.itemName)
            elseif not Notify.WasRecentlyShownByName(collectible.itemName) then
                DebugPrint("|cff00ff00[WN CollectionService]|r NEW " .. string.upper(collectible.type) .. " IN BAG: " .. collectible.itemName)

                Notify.MarkAsDetectedInBag(collectible.type, collectible.collectibleID)
                Notify.MarkAsNotified(collectible.type, collectible.collectibleID)
                Notify.MarkAsShownByName(collectible.itemName)
                if collectible.type == "pet" and collectible.itemID == collectible.collectibleID then
                    Notify.MarkPetNameBagCooldown(collectible.itemName)
                end

                if self.SendMessage then
                    self:SendMessage(E.COLLECTIBLE_OBTAINED, {
                        type = collectible.type,
                        id = collectible.collectibleID,
                        name = collectible.itemName,
                        icon = collectible.icon,
                        obtainedBy = Notify.CollectiblePayloadObtainedBy(),
                    })
                end
            else
                DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. collectible.itemName)
            end
        end
    end
end

function Scan.InstallBagScanListener()
    if Scan._bagScanInstalled then return end
    Scan._bagScanInstalled = true

    local bagScanFrame = CreateFrame("Frame")
    local bagScanTimer = nil
    local chatLootScanTimer = nil
    local BAG_SCAN_DEBOUNCE = 0.06
    local CHAT_LOOT_BAG_SCAN_DEBOUNCE = 0.04

    local function IsPossibleCollectibleLootItem(itemID)
        if not itemID then return false end
        local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
        if not classID then return true end
        if classID == 17 then return true end
        if classID == 15 then
            return subclassID == 5 or subclassID == 2 or subclassID == 0 or subclassID == 4
        end
        if classID == 0 then
            if C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID) then return true end
            if C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(itemID) then
                return true
            end
            return false
        end
        return false
    end

    local baselineInitialized = false
    local changedBagIDs = {}
    local suppressUntil = 0

    bagScanFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    bagScanFrame:RegisterEvent("BAG_UPDATE")
    bagScanFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    bagScanFrame:RegisterEvent("CHAT_MSG_LOOT")

    bagScanFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
        if not IsCollectionsModuleEnabled() then return end
        if event == "PLAYER_ENTERING_WORLD" then
            if not baselineInitialized then
                baselineInitialized = true
                if WarbandNexus and WarbandNexus.OnBagUpdateForCollectibles then
                    WarbandNexus:OnBagUpdateForCollectibles()
                end
                suppressUntil = GetTime() + 2.0
                DebugPrint("|cff9370DB[WN CollectionService]|r Bag scan baseline initialized (PLAYER_ENTERING_WORLD)")
            end
            return
        end

        if event == "BAG_UPDATE" then
            local bagID = arg1
            if bagID and bagID >= 0 and bagID <= 4 then
                changedBagIDs[bagID] = true
            end
            return
        end

        if event == "CHAT_MSG_LOOT" then
            if not baselineInitialized or GetTime() < suppressUntil then return end
            local message = arg1
            local author = arg2
            if not message or type(message) ~= "string" then return end
            if issecretvalue and issecretvalue(message) then return end
            if author and issecretvalue and issecretvalue(author) then return end
            local playerName = UnitName("player")
            if not playerName or (issecretvalue and issecretvalue(playerName)) then return end
            local authorBase = author and author:match("^([^%-]+)") or author
            if author and author ~= "" and author ~= playerName and (not authorBase or authorBase ~= playerName) then
                return
            end
            local itemIDStr = message:match("|Hitem:(%d+):")
            local itemID = itemIDStr and tonumber(itemIDStr) or nil
            if not itemID or not IsPossibleCollectibleLootItem(itemID) then return end
            if chatLootScanTimer then chatLootScanTimer:Cancel() end
            chatLootScanTimer = C_Timer.NewTimer(CHAT_LOOT_BAG_SCAN_DEBOUNCE, function()
                chatLootScanTimer = nil
                if not WarbandNexus or not WarbandNexus.OnBagUpdateForCollectibles then return end
                local bagsToScan = {}
                local hasBags = false
                for bagID in pairs(changedBagIDs) do
                    bagsToScan[bagID] = true
                    hasBags = true
                end
                wipe(changedBagIDs)
                if not hasBags then
                    bagsToScan[0] = true
                end
                Scan.lastCollectibleScanTime = 0
                WarbandNexus:OnBagUpdateForCollectibles(bagsToScan)
            end)
            return
        end

        if event ~= "BAG_UPDATE_DELAYED" then return end
        if not baselineInitialized then return end
        if GetTime() < suppressUntil then
            wipe(changedBagIDs)
            return
        end

        local hasInventoryChange = false
        for _ in pairs(changedBagIDs) do
            hasInventoryChange = true
            break
        end
        if not hasInventoryChange then return end

        if bagScanTimer then
            bagScanTimer:Cancel()
        end

        bagScanTimer = C_Timer.NewTimer(BAG_SCAN_DEBOUNCE, function()
            bagScanTimer = nil
            local bagsToScan = {}
            local hasBags = false
            for bagID in pairs(changedBagIDs) do
                bagsToScan[bagID] = true
                hasBags = true
            end
            wipe(changedBagIDs)

            if hasBags and WarbandNexus and WarbandNexus.OnBagUpdateForCollectibles then
                C_Timer.After(0, function()
                    if WarbandNexus and WarbandNexus.OnBagUpdateForCollectibles then
                        WarbandNexus:OnBagUpdateForCollectibles(bagsToScan)
                    end
                end)
            end
        end)
    end)
end

assert(Scan.InstallBagScanListener, "CollectionService_Scan: InstallBagScanListener missing")
