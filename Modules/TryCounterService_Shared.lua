--[[
    Warband Nexus - Try Counter shared constants and chat helpers.
    Split from TryCounterService.lua (IIFE chunk local budget).
    Loaded from WarbandNexus.toc immediately before Modules/TryCounterService.lua.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus

local format = string.format
local strfind = string.find
local tconcat = table.concat

local TC = {}
ns.TryCounter = TC

TC.VALID_TYPES = { mount = true, pet = true, toy = true, illusion = true, item = true }
TC.RECENT_KILL_TTL = 15
TC.PROCESSED_GUID_TTL = 300
TC.MERGED_LOOT_TRY_DEDUP_TTL = 600
TC.CLEANUP_INTERVAL = 60
TC.ENCOUNTER_OBJECT_TTL = 300
-- GetInstanceInfo()[8] map instanceID for Sanctum of Domination (warcraft.wiki.gg/wiki/InstanceID).
-- NOT the Encounter Journal instance id (1193); GetInstanceInfo never returns that value.
TC.SANCTUM_RAID_TEMPLATE_INSTANCE_ID = 2450
TC.RAID_MYTHIC_DIFFICULTY_ID = 16
-- Domination-Etched Treasure Cache: spawns on the Crucible platform after the Sylvanas cinematic.
-- 368304 ("Damaged Binding") was wrong and never matched a loot source.
TC.SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID = 369898

function TC.TryChat(message)
    local WarbandNexus = ns.WarbandNexus
    local dbg = ns.TryCounter and ns.TryCounter.Fns and ns.TryCounter.Fns.TryCounterAnnounceDebug
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
        and WarbandNexus.db.profile.notifications
        and WarbandNexus.db.profile.notifications.hideTryCounterChat then
        if dbg then dbg("TryChat: suppressed by hideTryCounterChat") end
        return
    end
    if ns.ChatOutput and ns.ChatOutput.SendTryCounterMessage then
        if dbg then dbg("TryChat: sink=ChatOutput") end
        ns.ChatOutput.SendTryCounterMessage(message)
    elseif ns.SendToChatFramesLootRepCurrency then
        if dbg then dbg("TryChat: sink=legacy loot frames") end
        ns.SendToChatFramesLootRepCurrency(message)
    elseif WarbandNexus and WarbandNexus.Print then
        if dbg then dbg("TryChat: sink=Print fallback") end
        WarbandNexus:Print(message)
    elseif dbg then
        dbg("TryChat: NO SINK AVAILABLE - line lost")
    end
end

function TC.BuildObtainedChat(baseKey, baseFallback, itemLink, preResetCount)
    local L = ns.L
    local prefix = "|cff9370DB[WN-Counter]|r "
    if preResetCount == nil then
        return prefix .. format((L and L[baseKey]) or baseFallback, itemLink)
    end
    local totalTries = preResetCount + 1
    local tags = {}
    if baseKey and strfind(baseKey, "CONTAINER", 1, true) then
        tags[#tags + 1] = (L and L["TRYCOUNTER_CHAT_TAG_CONTAINER"]) or "container"
    end
    if baseKey and strfind(baseKey, "CAUGHT", 1, true) then
        tags[#tags + 1] = (L and L["TRYCOUNTER_CHAT_TAG_FISHING"]) or "fishing"
    end
    if baseKey and strfind(baseKey, "RESET", 1, true) then
        tags[#tags + 1] = (L and L["TRYCOUNTER_CHAT_TAG_RESET"]) or "counter reset"
    end
    local tagStr = (#tags > 0) and (" |cff888888(" .. tconcat(tags, " · ") .. ")|r") or ""
    if totalTries <= 1 then
        local fmt = (L and L["TRYCOUNTER_CHAT_OBTAINED_FIRST_LINK"])
            or (L and L["TRYCOUNTER_CHAT_FIRST_FOR_LINK"])
            or "You got %s on your first try!"
        return prefix .. "|cffffffff" .. format(fmt, itemLink) .. "|r" .. tagStr
    end
    local fmt = (L and L["TRYCOUNTER_CHAT_OBTAINED_AFTER_LINK"])
        or "You got %s after %d attempts!"
    return prefix .. "|cffffffff" .. format(fmt, itemLink, totalTries) .. "|r" .. tagStr
end

--- Find the nearest eligible alt for a target entity / encounter / rare.
--- @param targetID number|string|nil Optional identifier (e.g. creatureID, encounterID, questID)
--- @param targetMapID number|nil Target zone uiMapID
--- @param targetX number|nil Target normalized map X coordinate (0-1)
--- @param targetY number|nil Target normalized map Y coordinate (0-1)
--- @return table|nil { bestAlt = table, allAlts = table }
function WarbandNexus:FindNearestEligibleAlt(targetID, targetMapID, targetX, targetY)
    if not self.db or not self.db.global or not self.db.global.characters then
        return nil
    end

    local candidates = {}
    local CS = ns.CharacterService
    local locs = CS and CS.GetAllCharacterLocations and CS:GetAllCharacterLocations(self) or {}

    for charKey, charData in pairs(self.db.global.characters) do
        local isEligible = true
        if targetID and self.IsDropEligible then
            local ok, eligible = pcall(self.IsDropEligible, self, charKey, targetID)
            if ok and eligible == false then
                isEligible = false
            end
        end

        local loc = locs[charKey] or {
            uiMapID = charData.uiMapID,
            zoneName = charData.zoneName or "",
            mapX = charData.mapX,
            mapY = charData.mapY,
            isResting = charData.isResting or false,
        }

        local score = 100
        local distDesc = "Distant"
        local charMap = loc and loc.uiMapID

        if targetMapID and charMap and charMap == targetMapID then
            if targetX and targetY and loc.mapX and loc.mapY then
                local dx = loc.mapX - targetX
                local dy = loc.mapY - targetY
                local d = math.sqrt(dx * dx + dy * dy)
                score = math.floor(d * 10)
                distDesc = string.format("In Zone (%.0f%% away)", d * 100)
            else
                score = 5
                distDesc = "In Same Zone"
            end
        elseif loc and loc.isResting then
            score = 30
            distDesc = (loc.zoneName and loc.zoneName ~= "") and ("Resting in " .. loc.zoneName) or "Resting in City"
        elseif loc and loc.zoneName and loc.zoneName ~= "" then
            score = 70
            distDesc = loc.zoneName
        end

        if not isEligible then
            score = score + 1000
        end

        candidates[#candidates + 1] = {
            charKey = charKey,
            charName = charData.name or charKey,
            classFile = charData.classFile or "PRIEST",
            uiMapID = charMap,
            zoneName = loc and loc.zoneName or "",
            mapX = loc and loc.mapX,
            mapY = loc and loc.mapY,
            score = score,
            distanceDesc = distDesc,
            isEligible = isEligible,
        }
    end

    table.sort(candidates, function(a, b)
        return a.score < b.score
    end)

    if #candidates > 0 then
        return {
            bestAlt = candidates[1],
            allAlts = candidates,
        }
    end
    return nil
end

