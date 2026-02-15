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

-- Message groups managed by this filter:
--   COMBAT_FACTION_CHANGE — Reputation gains/losses
--   CURRENCY              — Currency gains/losses (excluding gold)
--   MONEY                 — Gold gains/losses

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

---Compute effective enabled state for each notification type.
---A notification is "active" only when BOTH the master toggle AND the specific toggle are ON.
---@return boolean reputationActive
---@return boolean currencyActive
local function GetEffectiveState()
    local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not notifs or not notifs.enabled then
        return false, false  -- Master toggle OFF → restore ALL Blizzard messages
    end
    return notifs.showReputationGains == true, notifs.showCurrencyGains == true
end

---Initialize chat filter (call on addon load)
function WarbandNexus:InitializeChatFilter()
    local reputationActive, currencyActive = GetEffectiveState()
    UpdateMessageGroups(reputationActive, currencyActive)
end

---Update chat filter (call when any notification setting changes)
---Re-evaluates master + individual toggles and suppresses/restores Blizzard messages accordingly.
function WarbandNexus:UpdateChatFilter()
    local reputationActive, currencyActive = GetEffectiveState()
    UpdateMessageGroups(reputationActive, currencyActive)
end

-- Module loaded
-- Chat filter module loaded (silent)
