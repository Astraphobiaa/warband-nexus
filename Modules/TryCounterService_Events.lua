--[[
    Warband Nexus - Try Counter event tables (ops-030 slice)
    Loaded after TryCounterService_Shared.lua, before TryCounterService.lua.
]]

local _, ns = ...

local TC = ns.TryCounter or {}
ns.TryCounter = TC

TC.DEBUG_TRACE_EVENTS = {
    LOOT_READY = true,
    LOOT_OPENED = true,
    LOOT_CLOSED = true,
    CHAT_MSG_CURRENCY = true,
    CHAT_MSG_MONEY = true,
    ITEM_LOCK_CHANGED = true,
    UNIT_SPELLCAST_SENT = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    ENCOUNTER_START = true,
    ENCOUNTER_END = true,
    BOSS_KILL = true,
}

TC.TRYCOUNTER_EVENTS = {
    "LOOT_READY",
    "LOOT_OPENED",
    "LOOT_CLOSED",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_CURRENCY",
    "CHAT_MSG_MONEY",
    "ENCOUNTER_START",
    "ENCOUNTER_END",
    "BOSS_KILL",
    "PLAYER_ENTERING_WORLD",
    "UNIT_SPELLCAST_SENT",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED_QUIET",
    "ITEM_LOCK_CHANGED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "PLAYER_TARGET_CHANGED",
    "QUEST_LOG_UPDATE",
    "PLAYER_REGEN_ENABLED",
    "CRITERIA_UPDATE",
    "NEW_MOUNT_ADDED",
    "NEW_PET_ADDED",
}

-- Enum.PlayerInteractionType values that block ProcessNPCLoot (warcraft.wiki.gg/wiki/Enum.PlayerInteractionType)
TC.BLOCKING_INTERACTION_TYPES = {
    [1] = true,   -- TradePartner
    [5] = true,   -- Merchant
    [8] = true,   -- Banker
    [10] = true,  -- GuildBanker
    [17] = true,  -- MailInfo
    [21] = true,  -- Auctioneer
    [26] = true,  -- VoidStorageBanker
    [27] = true,  -- BlackMarketAuctioneer
    [31] = true,  -- GarrTradeskill
    [40] = true,  -- ScrappingMachine
    [44] = true,  -- ItemInteraction
}

assert(TC.TRYCOUNTER_EVENTS and TC.BLOCKING_INTERACTION_TYPES, "TryCounterService_Events: tables missing")
