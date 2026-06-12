--[[
    Warband Nexus - Daily quest plan hooks (ops-034 slice)
    QUEST_PROGRESS_UPDATED handler and quest completion notifications.
    Loaded before Modules/PlansManager.lua.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local E = Constants.EVENTS

--[[
    Handle daily quest progress updates from DailyQuestManager
]]
function WarbandNexus:OnDailyQuestProgressUpdated()
    -- Check if any daily quest plans were completed
    self:CheckPlansForCompletion()
end
--[[
    Show notification for completed daily quest
    @param characterName string - Character name
    @param category string - Quest category
    @param questTitle string - Quest title
]]
function WarbandNexus:ShowDailyQuestNotification(characterName, category, questTitle)
    self:Debug("Sending quest notification: " .. questTitle)
    
    -- Send quest completion event
    self:SendMessage(E.QUEST_COMPLETED, {
        characterName = characterName,
        category = category,
        questTitle = questTitle
    })
end
