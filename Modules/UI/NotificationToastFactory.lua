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
---@param options table|nil { strata?, frameLevel?, clampToScreen?, enableMouse?, globalName? }
---@return Frame
function NotificationToastFactory:CreateToastHost(parent, width, height, options)
    options = options or {}
    parent = parent or UIParent
    local Factory = ns.UI and ns.UI.Factory
    assert(Factory and Factory.CreateContainer, "NotificationToastFactory requires UI.Factory")
    local host = Factory:CreateContainer(parent, width, height, false, options.globalName)
    assert(host, "CreateToastHost failed")
    host:SetSize(width, height)
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

--- Layout/effects layer inside a toast host (Factory container; no ad-hoc CreateFrame in feature UI).
---@param parent Frame
---@param width number|nil
---@param height number|nil
---@return Frame
function NotificationToastFactory:CreateToastLayer(parent, width, height)
    local Factory = ns.UI and ns.UI.Factory
    assert(Factory and Factory.CreateContainer, "NotificationToastFactory requires UI.Factory")
    local layer = Factory:CreateContainer(parent, width or 1, height or 1, false)
    assert(layer, "CreateToastLayer failed")
    -- Factory containers are plain Frames; Midnight 12.0.7 has no Frame:SetBackdrop.
    -- Toast layers are used as backdrop shells, so retrofit BackdropTemplateMixin here.
    if BackdropTemplateMixin and not layer.SetBackdrop then
        Mixin(layer, BackdropTemplateMixin)
    end
    return layer
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
