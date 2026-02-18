--[[
    Warband Nexus - Chat Filter Service
    Suppress Blizzard's default reputation and currency messages when addon notifications are enabled
    
    Architecture:
    - Uses ChatFrame_AddMessageEventFilter to suppress messages globally across ALL chat frames
    - Non-destructive: does NOT modify the user's chat panel configuration
    - Dynamically reads settings per-message, so toggle changes take effect immediately
    - Addon's ChatMessageService injects enhanced replacements into the same panels
      via chatFrame:AddMessage() using frame:IsEventRegistered() routing
    
    Filtered events:
    - CHAT_MSG_COMBAT_FACTION_CHANGE — Reputation gains/losses
    - CHAT_MSG_CURRENCY              — Currency gains/losses
    
    NOT filtered (addon does not produce replacements for these):
    - CHAT_MSG_MONEY — Gold gains/losses (left to Blizzard)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local filtersInstalled = false

local function ShouldSuppressReputation()
    local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not notifs or not notifs.enabled then return false end
    return notifs.showReputationGains == true
end

local function ShouldSuppressCurrency()
    local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not notifs or not notifs.enabled then return false end
    return notifs.showCurrencyGains == true
end

local function ReputationFilter(self, event, msg, ...)
    if ShouldSuppressReputation() then
        return true
    end
    return false, msg, ...
end

local function CurrencyFilter(self, event, msg, ...)
    if ShouldSuppressCurrency() then
        return true
    end
    return false, msg, ...
end

---Install message event filters (once, on addon load).
---Filters check settings dynamically per-message, so no reinstall needed on toggle.
function WarbandNexus:InitializeChatFilter()
    if filtersInstalled then return end
    filtersInstalled = true

    ChatFrame_AddMessageEventFilter("CHAT_MSG_COMBAT_FACTION_CHANGE", ReputationFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CURRENCY", CurrencyFilter)
end

---No-op for backward compatibility (settings UI and Config.lua call this on toggle).
---Filters read settings dynamically, so no update action is needed.
function WarbandNexus:UpdateChatFilter()
    if not filtersInstalled then
        self:InitializeChatFilter()
    end
end
