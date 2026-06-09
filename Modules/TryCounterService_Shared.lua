--[[
    Warband Nexus - Try Counter shared constants and chat helpers.
    Split from TryCounterService.lua (IIFE chunk local budget).
    Loaded from WarbandNexus.toc immediately before Modules/TryCounterService.lua.
]]

local _, ns = ...

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
TC.SANCTUM_RAID_TEMPLATE_INSTANCE_ID = 1193
TC.RAID_MYTHIC_DIFFICULTY_ID = 16
TC.SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID = 368304

function TC.TryChat(message)
    local WarbandNexus = ns.WarbandNexus
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
        and WarbandNexus.db.profile.notifications
        and WarbandNexus.db.profile.notifications.hideTryCounterChat then
        return
    end
    if ns.ChatOutput and ns.ChatOutput.SendTryCounterMessage then
        ns.ChatOutput.SendTryCounterMessage(message)
    elseif ns.SendToChatFramesLootRepCurrency then
        ns.SendToChatFramesLootRepCurrency(message)
    elseif WarbandNexus and WarbandNexus.Print then
        WarbandNexus:Print(message)
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
