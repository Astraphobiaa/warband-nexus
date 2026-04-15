--[[
    Warband Nexus - Loading Tracker
    Centralized system for tracking initialization progress.
    Services register operations when starting and mark them complete when done.
    Fires WN_LOADING_UPDATED on every change and WN_LOADING_COMPLETE when all done.
]]

local addonName, ns = ...
local twipe = table.wipe
local E = ns.Constants.EVENTS

local Tracker = {}
ns.LoadingTracker = Tracker

local operations = {}
local orderedKeys = {}
local totalOps = 0
local completedOps = 0
local allComplete = false
-- Reused list for GetPendingLabels(); do not cache the return value across calls.
local pendingLabelsScratch = {}

-- Most consumers poll tracker state directly (UI sync bar).
-- Keep addon-message broadcasts opt-in to avoid startup event spam.
local function EmitLoadingMessage(eventName)
    if ns.LOADING_TRACKER_EMIT_MESSAGES ~= true then
        return
    end
    local addon = _G[addonName]
    if addon and addon.SendMessage then
        addon:SendMessage(eventName)
    end
end

function Tracker:Register(id, label)
    if operations[id] then return end
    operations[id] = { label = label, complete = false }
    orderedKeys[#orderedKeys + 1] = id
    totalOps = totalOps + 1
    allComplete = false
    EmitLoadingMessage(E.LOADING_UPDATED)
end

function Tracker:Complete(id)
    if not operations[id] or operations[id].complete then return end
    operations[id].complete = true
    completedOps = completedOps + 1
    EmitLoadingMessage(E.LOADING_UPDATED)
    if completedOps >= totalOps and totalOps > 0 then
        allComplete = true
        EmitLoadingMessage(E.LOADING_COMPLETE)
    end
end

function Tracker:GetProgress()
    return completedOps, totalOps
end

function Tracker:IsComplete()
    return allComplete or totalOps == 0
end

---@return table labels Ephemeral array; same table on every call (next call overwrites).
function Tracker:GetPendingLabels()
    twipe(pendingLabelsScratch)
    local n = 0
    for i = 1, #orderedKeys do
        local id = orderedKeys[i]
        local op = operations[id]
        if op and not op.complete then
            n = n + 1
            pendingLabelsScratch[n] = op.label
        end
    end
    return pendingLabelsScratch
end
