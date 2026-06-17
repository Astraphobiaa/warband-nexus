--[[
    Warband Nexus — toast visual identity per notification type.
    Per-type accent colors, static icon border, full-alpha icons.
]]

local ADDON_NAME, ns = ...

local ToastChrome = {}
ns.NotificationToastChrome = ToastChrome

local TYPE_CHROME = {
    mount = {
        accent = { 0.58, 0.50, 0.72 },
        labelKey = "TOAST_CAT_MOUNT",
        defaultLabel = "Mount collected",
    },
    pet = {
        accent = { 0.46, 0.62, 0.50 },
        labelKey = "TOAST_CAT_PET",
        defaultLabel = "Battle pet collected",
    },
    toy = {
        accent = { 0.70, 0.54, 0.40 },
        labelKey = "TOAST_CAT_TOY",
        defaultLabel = "Toy collected",
    },
    illusion = {
        accent = { 0.50, 0.58, 0.68 },
        labelKey = "TOAST_CAT_ILLUSION",
        defaultLabel = "Illusion collected",
    },
    achievement = {
        accent = { 0.78, 0.66, 0.40 },
        labelKey = "TOAST_CAT_ACHIEVEMENT",
        defaultLabel = "Achievement earned",
    },
    plan = {
        accent = { 0.48, 0.58, 0.72 },
        labelKey = "TOAST_CAT_PLAN",
        defaultLabel = "Plan completed",
    },
    item = {
        accent = { 0.68, 0.48, 0.50 },
        labelKey = "TOAST_CAT_ITEM",
        defaultLabel = "Rare drop",
    },
    title = {
        accent = { 0.62, 0.56, 0.72 },
        labelKey = "TOAST_CAT_TITLE",
        defaultLabel = "Title earned",
    },
    vault = {
        accent = { 0.42, 0.62, 0.64 },
        labelKey = "TOAST_CAT_VAULT",
        defaultLabel = "Great Vault",
    },
    reputation = {
        accent = { 0.48, 0.62, 0.46 },
        labelKey = "TOAST_CAT_REPUTATION",
        defaultLabel = "Renown gained",
    },
    quest = {
        accent = { 0.72, 0.64, 0.42 },
        labelKey = "TOAST_CAT_QUEST",
        defaultLabel = "Quest complete",
    },
    tryCounter = {
        accent = { 0.76, 0.62, 0.36 },
        labelKey = "TOAST_CAT_TRY_COUNTER",
        defaultLabel = "Finally!",
    },
    criteria = {
        accent = { 0.48, 0.60, 0.68 },
        labelKey = nil,
        defaultLabel = "Achievement Progress",
    },
}

local DEFAULT_CHROME = {
    accent = { 0.52, 0.50, 0.58 },
    labelKey = nil,
    defaultLabel = "Notification",
}

local CRITERIA_ACCENT = TYPE_CHROME.criteria.accent
local REMINDER_ACCENT = { 0.78, 0.66, 0.38 }

function ToastChrome.Resolve(notifType)
    local row = (notifType and TYPE_CHROME[notifType]) or DEFAULT_CHROME
    local L = ns.L
    local label = row.defaultLabel
    if row.labelKey and L and L[row.labelKey] then
        label = L[row.labelKey]
    end
    return {
        accent = { row.accent[1], row.accent[2], row.accent[3] },
        categoryLabel = label,
        softGlow = false,
    }
end

function ToastChrome.CriteriaAccent()
    return { CRITERIA_ACCENT[1], CRITERIA_ACCENT[2], CRITERIA_ACCENT[3] }
end

function ToastChrome.ReminderAccent()
    return { REMINDER_ACCENT[1], REMINDER_ACCENT[2], REMINDER_ACCENT[3] }
end

local function EnsureIconFullColor(iconTex)
    if not iconTex then return end
    if iconTex.SetVertexColor then
        iconTex:SetVertexColor(1, 1, 1, 1)
    end
    if iconTex.SetAlpha then
        iconTex:SetAlpha(1)
    end
end

---Static accent border around the icon; icon stays full color / full alpha.
function ToastChrome.ApplyCompactIconBorder(iconSlot, iconTex, iconSize, accentRGB)
    if not iconSlot or not iconTex then return end
    EnsureIconFullColor(iconTex)

    local r, g, b = 0.42, 0.42, 0.46
    if accentRGB then
        r = accentRGB[1]
        g = accentRGB[2]
        b = accentRGB[3]
    end

    local edgeSize = 2
    local border = CreateFrame("Frame", nil, iconSlot, "BackdropTemplate")
    border:SetFrameLevel((iconSlot.GetFrameLevel and iconSlot:GetFrameLevel() or 2) + 2)
    border:SetSize(iconSize + edgeSize * 2, iconSize + edgeSize * 2)
    border:SetPoint("CENTER", iconTex, "CENTER", 0, 0)
    border:EnableMouse(false)
    border:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        tile = false,
        edgeSize = edgeSize,
        insets = { left = edgeSize, right = edgeSize, top = edgeSize, bottom = edgeSize },
    })
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(r, g, b, 0.88)
end

function ToastChrome.ApplyCompactBackdropChrome(backdropFrame, accentRGB, borderAlpha)
    if not backdropFrame or not accentRGB then return end
    local r, g, b = accentRGB[1], accentRGB[2], accentRGB[3]
    local ba = borderAlpha or 0.38
    if backdropFrame.SetBackdropBorderColor then
        backdropFrame:SetBackdropBorderColor(r, g, b, ba)
    end
end

function ToastChrome.AccentHex(accentRGB, boost)
    if not accentRGB then return "|cffffffff" end
    boost = boost or 1.06
    local tr = math.floor(math.min(255, accentRGB[1] * 255 * boost))
    local tg = math.floor(math.min(255, accentRGB[2] * 255 * boost))
    local tb = math.floor(math.min(255, accentRGB[3] * 255 * boost))
    return string.format("|cff%02x%02x%02x", tr, tg, tb)
end

function ToastChrome.TitleHex(accentRGB)
    return ToastChrome.AccentHex(accentRGB, 1.14)
end

function ToastChrome.CategoryHex(accentRGB)
    return ToastChrome.AccentHex(accentRGB, 0.90)
end
