--[[
    Warband Nexus - Chat Filter Service
    Suppress Blizzard's default reputation and currency messages when addon notifications are enabled
    
    Architecture:
    - Removes message groups from ChatFrame1 (main chat window) when addon notifications are ON
    - Restores message groups when addon notifications are OFF
    - Uses ChatFrame API: ChatFrame_RemoveMessageGroup / ChatFrame_AddMessageGroup
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Message groups to suppress
local SUPPRESSED_MESSAGE_GROUPS = {
    "COMBAT_FACTION_CHANGE",  -- Reputation gains/losses
    "CURRENCY",               -- Currency gains/losses (excluding gold)
    "MONEY",                  -- Gold gains/losses
}

-- State tracking (per message group)
local originalChatState = {}

---Suppress or restore specific message groups based on settings
---@param reputationEnabled boolean Whether reputation notifications are ON
---@param currencyEnabled boolean Whether currency notifications are ON
local function UpdateMessageGroups(reputationEnabled, currencyEnabled)
    local chatFrame = _G.ChatFrame1
    if not chatFrame then
        return
    end
    
    -- REPUTATION: Suppress if addon notification is ON, restore if OFF
    if reputationEnabled then
        ChatFrame_RemoveMessageGroup(chatFrame, "COMBAT_FACTION_CHANGE")
    else
        ChatFrame_AddMessageGroup(chatFrame, "COMBAT_FACTION_CHANGE")
    end
    
    -- CURRENCY: Suppress if addon notification is ON, restore if OFF
    if currencyEnabled then
        ChatFrame_RemoveMessageGroup(chatFrame, "CURRENCY")
        ChatFrame_RemoveMessageGroup(chatFrame, "MONEY")
    else
        ChatFrame_AddMessageGroup(chatFrame, "CURRENCY")
        ChatFrame_AddMessageGroup(chatFrame, "MONEY")
    end
end

---Initialize chat filter (call on addon load)
function WarbandNexus:InitializeChatFilter()
    -- Check if notifications are enabled
    local reputationEnabled = self.db.profile.notifications and self.db.profile.notifications.showReputationGains
    local currencyEnabled = self.db.profile.notifications and self.db.profile.notifications.showCurrencyGains
    
    -- Update message groups based on settings
    UpdateMessageGroups(reputationEnabled, currencyEnabled)
end

---Update chat filter (call when settings change)
---@param reputationEnabled boolean Whether reputation notifications are enabled
---@param currencyEnabled boolean Whether currency notifications are enabled
function WarbandNexus:UpdateChatFilter(reputationEnabled, currencyEnabled)
    UpdateMessageGroups(reputationEnabled, currencyEnabled)
end

-- Module loaded
-- Chat filter module loaded (silent)
