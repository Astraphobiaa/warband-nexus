--[[
    Warband Nexus — Notification toast host factory
    Creates alert root frames via SharedWidgets Factory (no ad-hoc top-level Frame/Button in feature UI).
    Inner layers (textures, BackdropTemplate children) remain plain FrameXML children of the host.
]]

local ADDON_NAME, ns = ...
local NotificationToastFactory = {}
ns.NotificationToastFactory = NotificationToastFactory

---@param parent Frame|nil
---@param width number
---@param height number
---@param options table|nil { strata?, frameLevel?, clampToScreen?, enableMouse? }
---@return Frame
function NotificationToastFactory:CreateToastHost(parent, width, height, options)
    options = options or {}
    parent = parent or UIParent
    local Factory = ns.UI and ns.UI.Factory
    local host
    if Factory and Factory.CreateContainer then
        host = Factory:CreateContainer(parent, width, height, false)
    end
    if not host then
        host = CreateFrame("Frame", nil, parent)
        host:SetSize(width or 100, height or 100)
    else
        host:SetSize(width, height)
    end
    host:SetFrameStrata(options.strata or "HIGH")
    host:SetFrameLevel(options.frameLevel or 1000)
    if options.clampToScreen ~= false then
        host:SetClampedToScreen(true)
    end
    if options.enableMouse == false then
        host:EnableMouse(false)
    else
        host:EnableMouse(true)
    end
    return host
end
