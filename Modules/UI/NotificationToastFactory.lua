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

---Single compact-toast text layout: category top-right, title/detail left column (icon gutter + pad).
---@param params table
---@return nil
function NotificationToastFactory:ApplyCompactTextLayout(params)
    if not params or not params.contentFrame or not params.textGroup then return end
    local AS = ns.NotificationAlertStack
    local gapTitle = params.gapTitle or (AS and AS.ALERT_TEXT_LINE_GAP) or 2
    local textLeftPad = params.textLeftPad or (AS and AS.ALERT_PAD_TEXT) or 6
    local headerTopInset = params.headerTopInset
    if headerTopInset == nil and AS and AS.ToastPx then
        headerTopInset = AS.ToastPx(2)
    else
        headerTopInset = headerTopInset or 2
    end
    local contentFrame = params.contentFrame
    local textGroup = params.textGroup
    local headerLine = params.headerLine
    local titleLine = params.titleLine
    local detailLine = params.detailLine
    local textUseW = params.textUseW
    local stackH = params.stackH
    local hHeader = params.hHeader or 0
    local mode = params.mode or "standard"

    textGroup:SetSize(textUseW, stackH)
    textGroup:ClearAllPoints()
    if headerLine then headerLine:ClearAllPoints() end
    if titleLine then titleLine:ClearAllPoints() end
    if detailLine then detailLine:ClearAllPoints() end

    if mode == "tryCounter" then
        textGroup:SetPoint("LEFT", contentFrame, "LEFT", textLeftPad, 0)
        textGroup:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
        if titleLine then
            titleLine:SetJustifyH("LEFT")
            titleLine:SetWidth(textUseW)
            titleLine:SetPoint("TOPLEFT", textGroup, "TOPLEFT", 0, 0)
        end
        if headerLine and titleLine then
            headerLine:SetJustifyH("LEFT")
            headerLine:SetWidth(textUseW)
            headerLine:SetPoint("TOPLEFT", titleLine, "BOTTOMLEFT", 0, -gapTitle)
        end
        return
    end

    if mode == "legacySingle" then
        textGroup:SetPoint("LEFT", contentFrame, "LEFT", textLeftPad, 0)
        textGroup:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
        if headerLine then
            headerLine:SetJustifyH("LEFT")
            headerLine:SetWidth(textUseW)
            headerLine:SetPoint("TOPLEFT", textGroup, "TOPLEFT", 0, 0)
        end
        return
    end

    -- standard: collectible, achievement, progress, reminder — same left title column
    local titleCenterYOffset = 0
    if detailLine and titleLine then
        titleCenterYOffset = -math.floor((hHeader + headerTopInset) * 0.35)
    elseif headerLine then
        titleCenterYOffset = -math.floor((hHeader + headerTopInset + gapTitle) * 0.5)
    end
    if headerLine then
        if headerLine:GetParent() ~= contentFrame then
            headerLine:SetParent(contentFrame)
        end
        headerLine:SetJustifyH("RIGHT")
        local badgeW = textUseW + textLeftPad
        headerLine:SetWidth(badgeW)
        headerLine:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, -headerTopInset)
    end
    textGroup:SetPoint("LEFT", contentFrame, "LEFT", textLeftPad, 0)
    textGroup:SetPoint("CENTER", contentFrame, "CENTER", 0, titleCenterYOffset)
    if titleLine then
        titleLine:SetJustifyH("LEFT")
        titleLine:SetWidth(textUseW)
        titleLine:SetPoint("TOPLEFT", textGroup, "TOPLEFT", 0, 0)
    end
    if detailLine and titleLine then
        detailLine:SetJustifyH("LEFT")
        detailLine:SetWidth(textUseW)
        detailLine:SetPoint("TOPLEFT", titleLine, "BOTTOMLEFT", 0, -gapTitle)
    end
end
