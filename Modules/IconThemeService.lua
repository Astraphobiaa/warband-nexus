--[[
    Icon theme routing: Classic (Blizzard atlases / ReadyCheck) vs Modern (Atlas Icons PNGs).
    Plan slot states are defined in ns.PLAN_SLOT_STATE (SharedWidgets.lua).
]]

local ADDON_NAME, ns = ...

local WarbandNexus = ns.WarbandNexus

ns.ICON_THEME_CLASSIC = "classic"
ns.ICON_THEME_MODERN = "modern"

local MEDIA_ROOT = "Interface\\AddOns\\WarbandNexus\\Media\\"
local MEDIA_MODERN = MEDIA_ROOT .. "Modern\\"

--- Modern PNG paths (128px supersampled from Atlas Icons basic-ui, MIT).
local MODERN_TEXTURES = {
    complete = MEDIA_MODERN .. "WN-complete.png",
    not_complete = MEDIA_MODERN .. "WN-not-complete.png",
    todo_on = MEDIA_MODERN .. "WN-todo-on.png",
    todo_off = MEDIA_MODERN .. "WN-todo-off.png",
    track_on = MEDIA_MODERN .. "WN-track-on.png",
    track_off = MEDIA_MODERN .. "WN-track-off.png",
    delete = MEDIA_MODERN .. "WN-delete.png",
    reminder = MEDIA_MODERN .. "WN-reminder.png",
}

local STATE_TO_MODERN_KEY = {
    complete = "complete",
    not_complete = "not_complete",
    todo_on = "todo_on",
    todo_off = "todo_off",
    track_on = "track_on",
    track_off = "track_off",
    delete = "delete",
    reminder = "reminder",
}

local TODO_ATLAS_ON = "questbonusobjective-SuperTracked"
local TODO_ATLAS_OFF = "QuestBonusObjective"
local TRACK_ATLAS_ON = "VignetteKill-SuperTracked"
local TRACK_ATLAS_OFF = "VignetteKill"

function ns.GetIconTheme()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local t = db and db.iconTheme
    if t == ns.ICON_THEME_MODERN then
        return ns.ICON_THEME_MODERN
    end
    return ns.ICON_THEME_CLASSIC
end

function ns.IsModernIconTheme()
    return ns.GetIconTheme() == ns.ICON_THEME_MODERN
end

function ns.SetIconTheme(theme)
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then
        return
    end
    if theme == ns.ICON_THEME_MODERN then
        WarbandNexus.db.profile.iconTheme = ns.ICON_THEME_MODERN
    else
        WarbandNexus.db.profile.iconTheme = ns.ICON_THEME_CLASSIC
    end
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_ICON_THEME_CHANGED")
    end
end

function ns.IconTheme_GetModernTexture(state)
    local key = STATE_TO_MODERN_KEY[state]
    if not key then return nil end
    return MODERN_TEXTURES[key]
end

--- Apply modern slot icon; returns true if handled.
---@param tex Texture
---@param state string
---@param opts table|nil `{ iconPx, vertexColor, desaturate, disabled }`
function ns.IconTheme_ApplySlotState(tex, state, opts)
    opts = type(opts) == "table" and opts or {}
    if not tex or not state or not ns.IsModernIconTheme() then
        return false
    end
    local path = ns.IconTheme_GetModernTexture(state)
    if not path then return false end
    local iconPx = tonumber(opts.iconPx) or 24
    tex:SetTexture(path)
    tex:SetSize(iconPx, iconPx)
    local trim = tonumber(opts.texTrim) or 0.05
    if trim > 0 then
        tex:SetTexCoord(trim, 1 - trim, trim, 1 - trim)
    end
    if ns.UI_ConfigureCrispIconTexture then
        ns.UI_ConfigureCrispIconTexture(tex)
    end
    tex:SetDesaturated(opts.desaturate == true)
    local vc = opts.vertexColor
    if vc and #vc >= 3 then
        tex:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 1)
    elseif state == "delete" then
        tex:SetVertexColor(0.92, 0.38, 0.38, 1)
    elseif state == "reminder" then
        tex:SetVertexColor(0.72, 0.72, 0.76, 1)
    elseif state == "complete" or state == "todo_on" or state == "track_on" then
        tex:SetVertexColor(1, 0.84, 0.28, 1)
    elseif state == "not_complete" then
        tex:SetVertexColor(0.92, 0.38, 0.38, 1)
    elseif state == "todo_off" or state == "track_off" then
        tex:SetVertexColor(0.78, 0.80, 0.86, 1)
    else
        tex:SetVertexColor(1, 1, 1, 1)
    end
    if opts.disabled then
        tex:SetDesaturated(true)
        tex:SetVertexColor(0.55, 0.58, 0.62, 0.5)
    end
    return true
end

--- Classic descriptors for documentation / future use.
function ns.IconTheme_GetClassicAtlas(state)
    if state == "todo_on" then return TODO_ATLAS_ON end
    if state == "todo_off" then return TODO_ATLAS_OFF end
    if state == "track_on" then return TRACK_ATLAS_ON end
    if state == "track_off" then return TRACK_ATLAS_OFF end
    return nil
end
