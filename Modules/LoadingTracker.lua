--[[
    Warband Nexus - Loading Tracker
    Centralized system for tracking initialization progress.
    Services register operations when starting and mark them complete when done.
    Fires WN_LOADING_UPDATED on every change and WN_LOADING_COMPLETE when all done.
]]

local addonName, ns = ...

local Tracker = {}
ns.LoadingTracker = Tracker

local operations = {}
local orderedKeys = {}
local totalOps = 0
local completedOps = 0
local allComplete = false

function Tracker:Register(id, label)
    if operations[id] then return end
    operations[id] = { label = label, complete = false }
    orderedKeys[#orderedKeys + 1] = id
    totalOps = totalOps + 1
    allComplete = false
    local addon = _G[addonName]
    if addon and addon.SendMessage then
        addon:SendMessage("WN_LOADING_UPDATED")
    end
end

function Tracker:Complete(id)
    if not operations[id] or operations[id].complete then return end
    operations[id].complete = true
    completedOps = completedOps + 1
    local addon = _G[addonName]
    if addon and addon.SendMessage then
        addon:SendMessage("WN_LOADING_UPDATED")
    end
    if completedOps >= totalOps and totalOps > 0 then
        allComplete = true
        if addon and addon.SendMessage then
            addon:SendMessage("WN_LOADING_COMPLETE")
        end
    end
end

function Tracker:GetProgress()
    return completedOps, totalOps
end

function Tracker:IsComplete()
    return allComplete or totalOps == 0
end

function Tracker:GetPendingLabels()
    local pending = {}
    for _, id in ipairs(orderedKeys) do
        if not operations[id].complete then
            pending[#pending + 1] = operations[id].label
        end
    end
    return pending
end
